"""Cache splits for fine-tuning on one person's handwriting.

Each labelled dir holds candidates.json and labels.tsv (index<TAB>latex);
user_lines.py output also has pick.json, which maps label index to candidate.

<dir>_test: labelled expressions whose source (lecture PDF or notebook id)
            starts with one of --test-prefix.
user_mix:   every other labelled expression repeated --repeat times, plus a
            random sample of a base split so the model keeps its breadth
            (--base-split; the shipped model samples the synthetic one).
user_val:   --val-frac of the training labels, held out to pick checkpoints.
Same on-disk format as prepare.py; augmentation happens in InkDataset.

    python src/build_user_cache.py out/own out/held_out --train-only out/lectures \
        --test-prefix NOTEBOOK_ID --base-split cache_synth/train --val-frac 0.1 --dest cache_ft
"""
import argparse
import json
import random
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import features as feat_mod  # noqa: E402
from vocab import Vocab, tokenize  # noqa: E402


def write(dest, samples, meta):
    dest.mkdir(parents=True, exist_ok=True)
    pts = [p for p, _ in samples]
    tgt = [t for _, t in samples]
    np.concatenate(pts).astype(np.float16).tofile(dest / "points.f16")
    np.concatenate(tgt).astype(np.int16).tofile(dest / "target.i16")
    np.save(dest / "point_off.npy", np.cumsum([0] + [len(p) for p in pts]).astype(np.int64))
    np.save(dest / "target_off.npy", np.cumsum([0] + [len(t) for t in tgt]).astype(np.int64))
    (dest / "meta.json").write_text(json.dumps({**meta, "n_samples": len(samples)}, indent=1))


def labelled(d):
    """(source, strokes, latex) per label line."""
    cands = json.loads((d / "candidates.json").read_text())
    pick = json.loads((d / "pick.json").read_text()) if (d / "pick.json").exists() else None
    for line in (d / "labels.tsv").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        idx, label = line.split("\t", 1)
        c = cands[pick[int(idx)] if pick else int(idx)]
        yield c.get("pdf") or c["notebook"], c["strokes"], label.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("labelled", type=Path, nargs="+")
    ap.add_argument("--cache", type=Path, default=Path("cache"))
    ap.add_argument("--test-prefix", nargs="*", default=[], help="sources held out as <dir>_test")
    ap.add_argument("--repeat", type=int, default=30)
    ap.add_argument("--mathwriting", type=int, default=8000, help="how many inks to sample from the base split")
    ap.add_argument("--extra", type=Path, nargs="*", default=[], help="cache splits mixed in whole, e.g. cache/crohme")
    ap.add_argument("--val-frac", type=float, default=0.0,
                    help="hold this share of the training labels out as user_val, to pick checkpoints")
    ap.add_argument("--train-only", type=Path, nargs="*", default=[],
                    help="labelled dirs used for training only, never val or test (pseudo-labels, dictation)")
    ap.add_argument("--base-split", type=Path,
                    help="split sampled by --mathwriting instead of <cache>/train, e.g. a licence-clean synthetic one")
    ap.add_argument("--dest", type=Path, help="write the splits here instead of --cache")
    a = ap.parse_args()
    dest = a.dest or a.cache
    vocab = Vocab.load(a.cache / "vocab.json")
    meta = json.loads((a.cache / "train" / "meta.json").read_text())
    known = set(vocab.itos)
    train, train_only, n_unk = [], [], 0
    for d in a.labelled + a.train_only:
        test = []
        for source, strokes, label in labelled(d):
            if any(t not in known for t in tokenize(label)):
                n_unk += 1
                print("  out of vocab, skipped:", label)
                continue
            sample = (feat_mod.extract([np.asarray(s, dtype=np.float32) for s in strokes], step=meta["step"]),
                      np.asarray(vocab.encode(label)))
            if source.startswith(tuple(a.test_prefix)):
                test.append(sample)
            else:
                (train_only if d in a.train_only else train).append(sample)
        if test and d not in a.train_only:
            write(dest / f"{d.name}_test", test, {**meta, "split": f"{d.name}_test"})
            print(f"{d.name}_test {len(test)}")

    rng = random.Random(0)
    if a.val_frac:
        rng.shuffle(train)
        n_val = int(len(train) * a.val_frac)
        write(dest / "user_val", train[:n_val], {**meta, "split": "user_val"})
        train = train[n_val:]
        print(f"user_val {n_val}")
    train += train_only

    base = a.base_split or a.cache / "train"
    pts = np.memmap(base / "points.f16", dtype=np.float16, mode="r").reshape(-1, meta["n_features"])
    tgt = np.memmap(base / "target.i16", dtype=np.int16, mode="r")
    po, to = np.load(base / "point_off.npy"), np.load(base / "target_off.npy")
    mw = [(np.array(pts[po[i]:po[i + 1]]), np.array(tgt[to[i]:to[i + 1]]))
          for i in rng.sample(range(len(po) - 1), a.mathwriting)]
    extra = []
    for e in a.extra:
        em = json.loads((e / "meta.json").read_text())
        ep = np.fromfile(e / "points.f16", dtype=np.float16).reshape(-1, em["n_features"])
        et = np.fromfile(e / "target.i16", dtype=np.int16)
        eo, eto = np.load(e / "point_off.npy"), np.load(e / "target_off.npy")
        extra += [(ep[eo[i]:eo[i + 1]], et[eto[i]:eto[i + 1]]) for i in range(len(eo) - 1)]
    mix = train * a.repeat + mw + extra
    rng.shuffle(mix)
    write(dest / "user_mix", mix, {**meta, "split": "user_mix", "user": len(train), "train_only": len(train_only)})
    print(f"user train {len(train)} ({len(train_only)} train-only, x{a.repeat}) + {len(mw)} base + {len(extra)} extra; "
          f"{n_unk} skipped out of vocab")


if __name__ == "__main__":
    main()
