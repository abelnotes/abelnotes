"""One-off preprocessing: InkML tree -> flat memory-mappable cache.

Why this exists: MathWriting's train split is a quarter of a million individual
XML files. Parsing them costs far more than the forward pass, so doing it inside
the training loop would leave the GPU idle behind six CPU cores. Everything is
therefore parsed once into three flat arrays per split:

    points.f16    (total_points, 6)  every ink's features, concatenated
    point_off.npy (n_samples + 1,)   start of each ink inside points.f16
    target.i16    (total_tokens,)    every ink's token ids, concatenated
    target_off.npy(n_samples + 1,)   start of each target
    meta.json     step, feature count, vocab path, counts

float16 for the features: the values are normalized to roughly [-8, 8] with
three useful decimals, which fp16 holds comfortably, and halving the cache
halves the page-cache pressure during training. int16 for targets since the
vocabulary is a few hundred entries.

The vocabulary is built from the *training* split only and then reused for
valid/test — building it per split would let a test-only symbol silently become
a known token and flatter the score.

    python src/prepare.py data/mathwriting-2024 --splits train valid test
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

import features as feat_mod
from inkml import iter_split
from vocab import Vocab


def build_vocab(root: Path, out_dir: Path, min_count: int, splits: list[str]) -> Vocab:
    """Collects labels from the training split(s) and writes vocab.json."""
    labels = []
    for split in splits:
        labels += [ink.label for ink in iter_split(root, split) if ink.label]
    vocab = Vocab.build(labels, min_count=min_count)
    out_dir.mkdir(parents=True, exist_ok=True)
    vocab.save(out_dir / "vocab.json")
    dropped = sum(1 for c in vocab.counts.values() if c < min_count)
    print(f"vocab: {len(vocab)} entries from {len(labels)} labels "
          f"({dropped} tokens below min_count={min_count} folded into <unk>)")
    return vocab


def prepare_split(
    root: Path,
    split: str,
    out_dir: Path,
    vocab: Vocab,
    step: float,
    max_points: int,
    max_tokens: int,
) -> None:
    dest = out_dir / split
    dest.mkdir(parents=True, exist_ok=True)

    point_blocks: list[np.ndarray] = []
    target_blocks: list[np.ndarray] = []
    point_off = [0]
    target_off = [0]
    n_skipped_empty = n_skipped_long = n_truncated = 0
    t0 = time.time()

    for i, ink in enumerate(iter_split(root, split)):
        label = ink.label
        if not label or ink.n_points == 0:
            n_skipped_empty += 1
            continue
        ids = vocab.encode(label)  # includes BOS and EOS
        if len(ids) > max_tokens:
            # A target longer than the decoder can ever emit is not a training
            # signal, it is a guaranteed loss floor. Drop it and say how many.
            n_skipped_long += 1
            continue
        pts = feat_mod.extract(ink.strokes, step=step)
        if len(pts) == 0:
            n_skipped_empty += 1
            continue
        if len(pts) > max_points:
            # Truncating drops the tail of the expression while keeping its
            # label, which teaches the model to hallucinate the missing part.
            # Counted and reported rather than done quietly, so that a cache
            # built with too small a max_points is visible instead of just
            # mysteriously worse. Synthetic inks reach 1128 points where human
            # ones stop near 320, so the two splits do not share a sensible cap.
            n_truncated += 1
            pts = pts[:max_points]

        point_blocks.append(pts.astype(np.float16))
        target_blocks.append(np.asarray(ids, dtype=np.int16))
        point_off.append(point_off[-1] + len(pts))
        target_off.append(target_off[-1] + len(ids))

        if (i + 1) % 20000 == 0:
            print(f"  {split}: {i + 1} files, {time.time() - t0:.0f}s", flush=True)

    if not point_blocks:
        print(f"{split}: nothing usable, skipped")
        return

    np.concatenate(point_blocks).tofile(dest / "points.f16")
    np.concatenate(target_blocks).tofile(dest / "target.i16")
    np.save(dest / "point_off.npy", np.asarray(point_off, dtype=np.int64))
    np.save(dest / "target_off.npy", np.asarray(target_off, dtype=np.int64))

    n = len(point_blocks)
    (dest / "meta.json").write_text(json.dumps({
        "split": split,
        "n_samples": n,
        "n_features": feat_mod.N_FEATURES,
        "step": step,
        "max_points": max_points,
        "max_tokens": max_tokens,
        "skipped_empty": n_skipped_empty,
        "skipped_too_long": n_skipped_long,
        "truncated_points": n_truncated,
    }, indent=1))
    print(f"{split}: {n} samples  "
          f"({point_off[-1] / 1e6:.1f}M points, {target_off[-1] / 1e6:.2f}M tokens)  "
          f"skipped empty={n_skipped_empty} too_long={n_skipped_long} "
          f"truncated={n_truncated}  "
          f"{time.time() - t0:.0f}s")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path)
    ap.add_argument("--out", type=Path, default=Path("cache"))
    ap.add_argument("--splits", nargs="+", default=["train", "valid", "test"])
    ap.add_argument("--vocab-splits", nargs="+", default=["train"],
                    help="splits the vocabulary is counted over; keep test out of it")
    ap.add_argument("--step", type=float, default=0.05)
    ap.add_argument("--max-points", type=int, default=1024)
    ap.add_argument("--max-tokens", type=int, default=192)
    ap.add_argument("--min-count", type=int, default=5)
    ap.add_argument("--reuse-vocab", action="store_true",
                    help="load <out>/vocab.json instead of counting a new one")
    args = ap.parse_args()

    if args.reuse_vocab:
        # Preparing the synthetic split must not rebuild the vocabulary. A
        # second vocabulary would renumber every token, so a model pretrained on
        # synthetic data would decode its own ids into different symbols when
        # fine-tuned on the human cache. Measured on 3000 synthetic samples, the
        # human vocabulary covers them to 0.003% out-of-vocabulary (`\&`, twice),
        # so there is nothing to gain from a separate one anyway.
        vocab = Vocab.load(args.out / "vocab.json")
        print(f"reusing vocab: {len(vocab)} entries from {args.out / 'vocab.json'}")
    else:
        vocab = build_vocab(args.root, args.out, args.min_count, args.vocab_splits)
    for split in args.splits:
        prepare_split(args.root, split, args.out, vocab,
                      args.step, args.max_points, args.max_tokens)


if __name__ == "__main__":
    main()
