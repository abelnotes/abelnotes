"""Packs a checkpoint into the single binary the Dart runtime loads.

The app runs its own forward pass (see ml/README.md), so it needs the weights in
a form Dart can mmap into typed-data views without a parser. Layout:

    magic     4 bytes   "ABLM"
    version   uint32    FORMAT_VERSION
    jsonLen   uint32    length of the header that follows
    json      bytes     {"config": {...}, "vocab": [...], "tensors": [...]}
    payload   bytes     every tensor, concatenated, each 16-byte aligned

Each entry in "tensors" carries name, dtype, shape, byte offset and byte length.
Offsets are 16-byte aligned because Dart's typed-data views refuse a byte offset
that is not a multiple of the element size, and the largest element the runtime
uses is Float32x4 at 16 bytes — the SIMD matmul views a weight tensor as a
Float32x4List, so an f32 tensor landing on an 8-byte boundary would be rejected
at load. Offsets are explicit in the header, so a reader needs no change and the
format version does not move.

Weights are stored as float16 and widened to float32 on load. That halves the
download for a model whose whole point is not bloating the app, and the accuracy
cost is measured rather than assumed: `--check-fp16` re-scores the rounded
weights against the unrounded ones on the validation split and prints both.
Inference itself stays in float32; only storage is narrowed.

Also writes `testvectors.bin` in the same container: real inks, their reference
memory tensor and the reference greedy token ids. That file is what lets the Dart
port be verified instead of hoped about — a transformer written by hand agrees
with PyTorch or it does not, and finding out at the layer level beats finding out
from a wrong formula on screen.

    python src/export_dart.py --checkpoint out/model/best.pt --out out/model/dart
    python src/export_dart.py --checkpoint out/model/best.pt --check-fp16
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).parent))

import features as feat_mod
from dataset import InkDataset, collate
from inkml import iter_split
from metrics import Scores
from model import Config, InkToLatex
from vocab import BOS_ID, EOS_ID, PAD_ID, Vocab, tokenize

MAGIC = b"ABLM"
FORMAT_VERSION = 1
ALIGN = 16


class Container:
    """Accumulates named tensors, then writes the aligned binary."""

    def __init__(self, header: dict):
        self.header = dict(header)
        self.entries: list[dict] = []
        self.blobs: list[bytes] = []
        self.offset = 0

    def add(self, name: str, array: np.ndarray, dtype: str) -> None:
        np_dtype = {"f16": np.float16, "f32": np.float32, "i32": np.int32}[dtype]
        data = np.ascontiguousarray(array, dtype=np_dtype).tobytes()
        pad = (-self.offset) % ALIGN
        if pad:
            self.blobs.append(b"\0" * pad)
            self.offset += pad
        self.entries.append({
            "name": name,
            "dtype": dtype,
            "shape": list(array.shape),
            "offset": self.offset,
            "bytes": len(data),
        })
        self.blobs.append(data)
        self.offset += len(data)

    def write(self, path: Path) -> int:
        header = dict(self.header, tensors=self.entries)
        blob = json.dumps(header, separators=(",", ":")).encode()
        # Pad the header with spaces (JSON ignores trailing whitespace) so the
        # payload itself starts on an ALIGN boundary. Without this the per-tensor
        # offsets are aligned only relative to the payload, and since the header
        # is variable-length the absolute offsets land anywhere — which is where a
        # typed-data view in Dart refuses to be created.
        blob += b" " * ((-(12 + len(blob))) % ALIGN)
        with open(path, "wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<II", FORMAT_VERSION, len(blob)))
            f.write(blob)
            for chunk in self.blobs:
                f.write(chunk)
        return path.stat().st_size


def load_checkpoint(checkpoint: Path, device: str = "cpu") -> tuple[InkToLatex, Config, dict]:
    ckpt = torch.load(checkpoint, map_location="cpu")
    raw = dict(ckpt["config"])
    raw["stem_strides"] = tuple(raw.get("stem_strides", (2, 2)))
    cfg = Config(**raw)
    model = InkToLatex(cfg)
    model.load_state_dict(ckpt["model"])
    return model.to(device).eval(), cfg, ckpt


def pack_weights(model: InkToLatex, cfg: Config, vocab: Vocab, out: Path, dtype: str) -> int:
    container = Container({
        "kind": "weights",
        "config": {k: (list(v) if isinstance(v, tuple) else v) for k, v in cfg.__dict__.items()},
        "vocab": vocab.itos,
        "bos_id": BOS_ID,
        "eos_id": EOS_ID,
        "pad_id": PAD_ID,
        "storage_dtype": dtype,
    })
    state = model.state_dict()
    # Sorted so the file is reproducible and a diff between two exports is
    # meaningful. The tied head weight aliases the embedding, and state_dict
    # reports both names for the same storage; keeping both costs a duplicate of
    # the largest tensor, so the head is dropped and Dart reuses the embedding.
    for name in sorted(state):
        if name == "decoder.head.weight":
            continue
        container.add(name, state[name].detach().cpu().numpy(), dtype)
    return container.write(out)


def pack_test_vectors(
    model: InkToLatex, cfg: Config, vocab: Vocab, data_root: Path, out: Path, n: int, step: float
) -> int:
    """Reference inputs and outputs for the Dart parity test.

    Vectors start from **raw ink**, not from the preprocessed cache. Feeding Dart
    the cached features would leave the whole feature pipeline — height
    normalization, arc-length resampling, the six channels — unverified, and that
    is exactly the half where a silent disagreement produces confident nonsense
    instead of an error. So each vector carries:

        strokes_i     raw (x, y) of every point, all strokes concatenated
        strokeOff_i   where each stroke starts inside strokes_i
        features_i    what features.extract must produce from those strokes
        memory_i      what the encoder must produce from those features
        tokens_i      what the greedy loop must emit

    Batch size 1 throughout, because that is what the app runs and therefore what
    has to match.
    """
    container = Container({
        "kind": "testvectors",
        "step": step,
        "note": "batch 1, float32 reference from PyTorch, greedy decode",
    })
    labels: list[str] = []
    predictions: list[str] = []
    inks = []
    for ink in iter_split(data_root, "valid"):
        if ink.label and ink.n_points > 0:
            inks.append(ink)
        if len(inks) >= n * 40:
            break
    # Spread the picks so the set is not all short inks.
    stride = max(len(inks) // n, 1)
    picked = [inks[i * stride] for i in range(min(n, len(inks) // stride))]

    for i, ink in enumerate(picked):
        strokes = [s[:, :2] for s in ink.strokes if len(s) > 0]
        offsets = np.cumsum([0] + [len(s) for s in strokes]).astype(np.int32)
        flat = np.concatenate(strokes, axis=0).astype(np.float32)

        feats = feat_mod.extract(ink.strokes, step=step)
        pts = torch.from_numpy(feats)[None]
        mask = torch.ones(1, pts.shape[1], dtype=torch.bool)
        with torch.no_grad():
            memory, _ = model.encoder(pts, mask)
            tokens = model.greedy(pts, mask, BOS_ID, EOS_ID, max_len=cfg.max_target_len)[0]

        container.add(f"strokes_{i}", flat, "f32")
        container.add(f"strokeOff_{i}", offsets, "i32")
        container.add(f"features_{i}", feats, "f32")
        container.add(f"memory_{i}", memory[0].numpy(), "f32")
        container.add(f"tokens_{i}", np.asarray(tokens, dtype=np.int32), "i32")
        labels.append(ink.label)
        predictions.append(vocab.decode(tokens))

    container.header["n"] = len(picked)
    # Both strings go in the header so a failing Dart test can print what the
    # model was supposed to say, not just which float went wrong. `labels` is the
    # ground truth; `predictions` is what this checkpoint actually emits, and it
    # is `predictions` that Dart must reproduce — reproducing the ground truth
    # would mean the port is better than the model, which would mean it is wrong.
    container.header["labels"] = labels
    container.header["predictions"] = predictions
    return container.write(out)


@torch.no_grad()
def check_fp16(model: InkToLatex, cfg: Config, cache: Path, vocab: Vocab,
               device: str, batches: int) -> None:
    """Scores float32 weights against float16-rounded ones on the same inks.

    The question is narrow: does narrowing *storage* to fp16 cost accuracy? So
    both runs compute in fp32 and differ only in that the second one's weights
    have been through a float16 round trip.
    """
    ds = InkDataset(cache, "valid", augment=False)
    # Evenly spaced across the split rather than the first N, which would be the
    # shortest inks: the cache preserves file order, but short expressions are
    # where the model is strongest and rounding would look free.
    n_wanted = batches * 32
    stride = max(len(ds) // n_wanted, 1)
    picks = [ds[i * stride] for i in range(min(n_wanted, len(ds) // stride))]
    batch = [picks[i : i + 32] for i in range(0, len(picks), 32)]

    def score(m: InkToLatex) -> Scores:
        out = Scores()
        for group in batch:
            if not group:
                continue
            points, mask, _, tok_out = collate(group, PAD_ID)
            points, mask = points.to(device), mask.to(device)
            preds = m.greedy(points, mask, BOS_ID, EOS_ID, max_len=cfg.max_target_len)
            for row, pred in zip(tok_out.tolist(), preds):
                ref = vocab.decode([t for t in row if t not in (PAD_ID, EOS_ID)])
                out.add(tokenize(ref), tokenize(vocab.decode(pred)))
        return out

    base = score(model.to(device))

    rounded = InkToLatex(cfg)
    rounded.load_state_dict({
        k: v.half().float() for k, v in model.state_dict().items()
    })
    narrow = score(rounded.to(device).eval())

    worst = max(
        (v - v.half().float()).abs().max().item() for v in model.state_dict().values()
    )
    print(f"  float32 weights  {base}")
    print(f"  float16 weights  {narrow}")
    print(f"  ExpRate delta {(narrow.exp_rate - base.exp_rate) * 100:+.2f} pts, "
          f"CER delta {(narrow.cer - base.cer) * 100:+.2f} pts, "
          f"largest weight change {worst:.2e}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--cache", type=Path, default=Path("cache"))
    ap.add_argument("--out", type=Path, default=None, help="output dir; omit to only check")
    ap.add_argument("--dtype", default="f16", choices=["f16", "f32"])
    ap.add_argument("--vectors", type=int, default=8)
    ap.add_argument("--data-root", type=Path, default=Path("data/mathwriting-2024"),
                    help="raw InkML tree; test vectors start from raw ink, not the cache")
    ap.add_argument("--step", type=float, default=0.05,
                    help="must match the step the cache was built with")
    ap.add_argument("--check-fp16", action="store_true")
    ap.add_argument("--check-batches", type=int, default=20)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = ap.parse_args()

    vocab = Vocab.load(args.cache / "vocab.json")
    model, cfg, ckpt = load_checkpoint(args.checkpoint)
    print(f"{args.checkpoint} epoch {ckpt.get('epoch')}  {model.n_params() / 1e6:.2f}M params  "
          f"vocab {cfg.n_vocab}")

    if args.check_fp16:
        print("float16 storage check:")
        check_fp16(model, cfg, args.cache, vocab, args.device, args.check_batches)
        model = model.cpu()

    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        size = pack_weights(model.cpu(), cfg, vocab, args.out / "weights.bin", args.dtype)
        print(f"  weights.bin      {size / 1e6:6.2f} MB  ({args.dtype})")
        size = pack_test_vectors(model.cpu(), cfg, vocab, args.data_root,
                                 args.out / "testvectors.bin", args.vectors, args.step)
        print(f"  testvectors.bin  {size / 1e6:6.2f} MB  ({args.vectors} inks)")


if __name__ == "__main__":
    main()
