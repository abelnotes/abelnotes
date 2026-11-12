"""Scores a checkpoint on a whole split. This is the number to quote.

train.py's per-epoch validation deliberately looks at a few hundred inks so it
stays cheap enough to run every epoch. That is fine for ranking checkpoints and
useless as a reported result: the sampling error on a 640-sample ExpRate is
around two points. This runs the entire split, and offers beam search, which
the training loop does not.

    python src/evaluate.py --checkpoint out/model/best.pt --cache cache --split test
    python src/evaluate.py --checkpoint out/model/best.pt --split test --beam 4

Reports ExpRate and token CER, plus a breakdown by target length, because a
single aggregate hides the thing that matters for the app: short expressions are
nearly solved while long ones are not, and it is the long ones that decide
whether a user trusts the feature.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import torch

sys.path.insert(0, str(Path(__file__).parent))

from dataset import InkDataset, collate
from metrics import Scores, edit_distance
from model import Config, InkToLatex
from train import make_loader
from vocab import BOS_ID, EOS_ID, PAD_ID, Vocab, tokenize


def load(checkpoint: Path, device: str) -> tuple[InkToLatex, Config, int]:
    ckpt = torch.load(checkpoint, map_location="cpu")
    raw = dict(ckpt["config"])
    raw["stem_strides"] = tuple(raw.get("stem_strides", (2, 2)))
    cfg = Config(**raw)
    model = InkToLatex(cfg)
    model.load_state_dict(ckpt["model"])
    return model.to(device).eval(), cfg, ckpt.get("epoch", -1)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--cache", type=Path, default=Path("cache"))
    ap.add_argument("--split", default="test")
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--batch-size", type=int, default=64)
    ap.add_argument("--beam", type=int, default=1, help="1 means greedy")
    ap.add_argument("--length-alpha", type=float, default=0.7)
    ap.add_argument("--limit", type=int, default=0, help="0 evaluates the whole split")
    ap.add_argument("--show", type=int, default=10, help="how many failures to print")
    args = ap.parse_args()

    vocab = Vocab.load(args.cache / "vocab.json")
    model, cfg, epoch = load(args.checkpoint, args.device)
    ds = InkDataset(args.cache, args.split, augment=False)
    loader = make_loader(ds, args.batch_size, workers=2, seed=0)

    mode = "greedy" if args.beam <= 1 else f"beam {args.beam} (alpha {args.length_alpha})"
    print(f"{args.checkpoint} epoch {epoch}  {cfg.n_encoder_layers}+{cfg.n_decoder_layers} "
          f"layers d={cfg.d_model}  {args.split} n={len(ds)}  {mode}")

    scores = Scores()
    # Buckets chosen from the corpus percentiles: p50 is 15 tokens, p99 is 42.
    buckets = [(0, 10), (10, 20), (20, 30), (30, 1000)]
    per_bucket = {b: Scores() for b in buckets}
    failures: list[tuple[str, str]] = []
    t0 = time.time()
    n_done = 0

    for points, mask, _, tok_out in loader:
        points, mask = points.to(args.device), mask.to(args.device)
        if args.beam <= 1:
            preds = model.greedy(points, mask, BOS_ID, EOS_ID, max_len=cfg.max_target_len)
        else:
            preds = model.beam(points, mask, BOS_ID, EOS_ID, pad=PAD_ID,
                               beam_size=args.beam, max_len=cfg.max_target_len,
                               length_alpha=args.length_alpha)

        for row, pred_ids in zip(tok_out.tolist(), preds):
            ref_ids = [t for t in row if t not in (PAD_ID, EOS_ID)]
            ref, pred = vocab.decode(ref_ids), vocab.decode(pred_ids)
            ref_tok, pred_tok = tokenize(ref), tokenize(pred)
            scores.add(ref_tok, pred_tok)
            for lo, hi in buckets:
                if lo <= len(ref_tok) < hi:
                    per_bucket[(lo, hi)].add(ref_tok, pred_tok)
                    break
            if ref_tok != pred_tok and len(failures) < args.show:
                failures.append((ref, pred))

        n_done += points.shape[0]
        if args.limit and n_done >= args.limit:
            break

    dt = time.time() - t0
    print(f"\n{scores}")
    print(f"{n_done} inks in {dt:.0f}s = {n_done / dt:.0f} ink/s on {args.device}")

    print("\nby target length")
    for (lo, hi), s in per_bucket.items():
        if s.n:
            label = f"{lo}-{hi - 1} tokens" if hi < 1000 else f"{lo}+ tokens"
            print(f"  {label:16s} {s}")

    if failures:
        print("\nfailures")
        for ref, pred in failures:
            # Point at the first token that differs; scanning two long LaTeX
            # strings by eye is exactly the tedium this avoids.
            rt, pt = tokenize(ref), tokenize(pred)
            at = next((i for i, (a, b) in enumerate(zip(rt, pt)) if a != b), min(len(rt), len(pt)))
            print(f"  ref  {ref}\n  pred {pred}\n       diverges at token {at}, "
                  f"edit distance {edit_distance(rt, pt)}")


if __name__ == "__main__":
    main()
