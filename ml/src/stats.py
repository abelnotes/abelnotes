"""Corpus survey: picks the hyperparameters that must match the data.

Three numbers come out of here and go straight into the model config:
  - encoder max_len      <- point-sequence length at the 99th percentile
  - decoder max_len      <- target token length at the 99th percentile
  - output vocabulary    <- number of distinct LaTeX tokens

Run it before training, and re-run it whenever `features.step` changes: the
sequence length scales inversely with the step, so halving the step doubles the
memory the encoder's attention needs.

    python src/stats.py data/mathwriting-2024 --split train --limit 5000
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

import features
import vocab as vocab_mod
from inkml import iter_split


def percentiles(values: list[int], qs=(50, 90, 95, 99, 100)) -> str:
    arr = np.asarray(values)
    return "  ".join(f"p{q}={int(np.percentile(arr, q))}" for q in qs)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path, help="dataset root holding the split dirs")
    ap.add_argument("--split", default="train")
    ap.add_argument("--limit", type=int, default=2000)
    ap.add_argument("--step", type=float, default=features.__dict__.get("_DEFAULT_STEP", 0.05))
    args = ap.parse_args()

    raw_points, feat_lens, tok_lens, stroke_counts = [], [], [], []
    labels: list[str] = []
    n_empty_label = n_empty_ink = 0

    for ink in iter_split(args.root, args.split, limit=args.limit):
        label = ink.label
        if not label:
            n_empty_label += 1
            continue
        if ink.n_points == 0:
            n_empty_ink += 1
            continue
        feats = features.extract(ink.strokes, step=args.step)
        labels.append(label)
        raw_points.append(ink.n_points)
        feat_lens.append(len(feats))
        tok_lens.append(len(vocab_mod.tokenize(label)))
        stroke_counts.append(len(ink.strokes))

    if not labels:
        print(f"no usable samples under {args.root / args.split}")
        return

    v = vocab_mod.Vocab.build(labels)
    counts: Counter = v.counts

    print(f"samples usable      {len(labels)}")
    print(f"  skipped: no label {n_empty_label}   no ink {n_empty_ink}")
    print(f"strokes / ink       {percentiles(stroke_counts)}")
    print(f"raw points / ink    {percentiles(raw_points)}")
    print(f"feature len (step={args.step})  {percentiles(feat_lens)}")
    print(f"target tokens / ink {percentiles(tok_lens)}")
    print(f"distinct tokens     {len(counts)}  (vocab with specials: {len(v)})")
    print(f"  seen once only    {sum(1 for c in counts.values() if c == 1)}")
    print(f"  seen >= 5 times   {sum(1 for c in counts.values() if c >= 5)}")
    print("most common 25      " + " ".join(t for t, _ in counts.most_common(25)))
    rare = [t for t, c in counts.most_common() if c == 1][:20]
    if rare:
        print("singletons (sample) " + " ".join(rare))


if __name__ == "__main__":
    main()
