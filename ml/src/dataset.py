"""Torch Dataset over the flat cache, plus the training-time ink augmentation.

The augmentation is the part worth reading. It is applied to the *cached*
features rather than to raw strokes, which works because every transform used
here is linear in the point coordinates:

    x' = A x + t        with A a 2x2 matrix

and the cached dx/dy channels are differences of coordinates, so they transform
under the same A with the translation cancelling out:

    dx' = A x_i - A x_{i-1} = A dx

That means rotation, shear and anisotropic scaling can be applied to channels
0:2 and 2:4 with one matrix multiply each and no re-resampling — resampling is
what would otherwise have to be redone, since a rotated stroke has a different
arc length parameterization. Only pure scaling changes arc length enough to
matter, and it is kept small for that reason.

Why these particular transforms: slant (shear along x) is the single largest
source of variation between writers; small rotation covers a tilted tablet; mild
anisotropic scale covers people who write tall or wide. Translation is *not*
augmented, because features.normalize_strokes already centres every ink, so
absolute position carries no writer-specific offset to be robust to.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import Dataset


class InkDataset(Dataset):
    def __init__(
        self,
        cache_dir: str | Path,
        split: str,
        augment: bool = False,
        max_rotate_deg: float = 4.0,
        max_shear: float = 0.30,
        max_log_scale: float = 0.12,
        point_dropout: float = 0.0,
        limit: int | None = None,
        limit_seed: int = 0,
    ):
        base = Path(cache_dir) / split
        self.meta = json.loads((base / "meta.json").read_text())
        n_feat = self.meta["n_features"]

        self.point_off = np.load(base / "point_off.npy")
        self.target_off = np.load(base / "target_off.npy")
        self.points = np.memmap(base / "points.f16", dtype=np.float16, mode="r").reshape(-1, n_feat)
        self.target = np.memmap(base / "target.i16", dtype=np.int16, mode="r")

        # `limit` answers "how much handwriting is enough": training the same
        # recipe on 1k, 4k, 16k inks and reading the accuracy curve. A random
        # subset rather than the first N, because the cache preserves file order
        # and the head of the split is not a fair sample of it. Sorted after
        # drawing so the memmap is still read roughly front-to-back, and seeded so
        # two runs at the same size see the same inks.
        n = len(self.point_off) - 1
        if limit is not None and 0 < limit < n:
            rng = np.random.default_rng(limit_seed)
            self.index = np.sort(rng.choice(n, size=limit, replace=False)).astype(np.int64)
        else:
            self.index = np.arange(n, dtype=np.int64)

        self.augment = augment
        self.max_rotate = math.radians(max_rotate_deg)
        self.max_shear = max_shear
        self.max_log_scale = max_log_scale
        self.point_dropout = point_dropout
        self._rng: np.random.Generator | None = None

    def _generator(self) -> np.random.Generator:
        """One Generator per worker process, created on first use.

        Building a fresh Generator per sample costs more than the augmentation
        it feeds: with that in place the loader sustained 180 samples/s against
        the GPU's 536, so data loading, not the model, set the epoch time.

        Creating it lazily rather than in __init__ is what makes it per-worker.
        DataLoader forks after construction, so an eagerly built Generator would
        be *copied* into every worker and all of them would draw the same
        stream. torch.initial_seed() differs per worker and already folds in the
        epoch, so seeding from it gives independent streams that still respond
        to a manual_seed.
        """
        if self._rng is None:
            self._rng = np.random.default_rng(torch.initial_seed() % (2**32))
        return self._rng

    def __len__(self) -> int:
        return len(self.index)

    @property
    def lengths(self) -> np.ndarray:
        """Point count per sample, in dataset order — what the bucket sampler
        batches by. Goes through `index`, so a subset buckets its own inks."""
        return np.diff(self.point_off)[self.index]

    def _random_matrix(self, rng: np.random.Generator) -> np.ndarray:
        theta = rng.uniform(-self.max_rotate, self.max_rotate)
        shear = rng.uniform(-self.max_shear, self.max_shear)
        sx, sy = np.exp(rng.uniform(-self.max_log_scale, self.max_log_scale, size=2))
        rot = np.array([[math.cos(theta), -math.sin(theta)],
                        [math.sin(theta), math.cos(theta)]], dtype=np.float32)
        shr = np.array([[1.0, shear], [0.0, 1.0]], dtype=np.float32)
        scl = np.array([[sx, 0.0], [0.0, sy]], dtype=np.float32)
        return (rot @ shr @ scl).astype(np.float32)

    def __getitem__(self, i: int):
        i = int(self.index[i])
        p0, p1 = self.point_off[i], self.point_off[i + 1]
        t0, t1 = self.target_off[i], self.target_off[i + 1]
        pts = np.asarray(self.points[p0:p1], dtype=np.float32)
        ids = np.asarray(self.target[t0:t1], dtype=np.int64)

        if self.augment:
            rng = self._generator()
            m = self._random_matrix(rng)
            pts[:, 0:2] = pts[:, 0:2] @ m.T
            pts[:, 2:4] = pts[:, 2:4] @ m.T
            if self.point_dropout > 0 and len(pts) > 8:
                # Simulates a digitizer dropping samples. Stroke start/end flags
                # are preserved: losing them would corrupt the stroke structure
                # rather than model a plausible sensor glitch.
                keep = rng.random(len(pts)) > self.point_dropout
                keep |= (pts[:, 4] > 0) | (pts[:, 5] > 0)
                pts = pts[keep]

        return torch.from_numpy(pts), torch.from_numpy(ids)


def collate(batch, pad_id: int = 0):
    """Pads a batch to its own longest ink and longest target.

    Returns points (B, L, F), point_mask (B, L) True on real points,
    tokens_in (B, T-1), tokens_out (B, T-1). The decoder is fed the target
    shifted right and scored against it shifted left, which is why a target of
    length T yields T-1 positions.
    """
    max_p = max(p.shape[0] for p, _ in batch)
    max_t = max(t.shape[0] for _, t in batch)
    n_feat = batch[0][0].shape[1]
    b = len(batch)

    points = torch.zeros(b, max_p, n_feat)
    point_mask = torch.zeros(b, max_p, dtype=torch.bool)
    tokens = torch.full((b, max_t), pad_id, dtype=torch.long)

    for i, (p, t) in enumerate(batch):
        points[i, : p.shape[0]] = p
        point_mask[i, : p.shape[0]] = True
        tokens[i, : t.shape[0]] = t

    return points, point_mask, tokens[:, :-1].contiguous(), tokens[:, 1:].contiguous()
