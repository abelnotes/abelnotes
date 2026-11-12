"""Contact sheets of labelled candidates: the ink above its label typeset.

Reading LaTeX source against handwriting misses things a glance at the typeset
label catches (a dropped brace, a subscript on the wrong symbol), so labels are
checked this way before they are trained on.

    python src/label_review.py out/user_nb --labels out/user_nb/labels.tsv --out out/user_nb/review
"""
import argparse
import io
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

sys.path.insert(0, str(Path(__file__).parent))
from notebook_lines import render  # noqa: E402

# mathtext lacks a few commands the vocabulary has.
_MATHTEXT = {r"\triangleq": r"\stackrel{\Delta}{=}", r"\iff": r"\Leftrightarrow"}


def typeset(latex, height=48):
    s = latex
    for a, b in _MATHTEXT.items():
        s = s.replace(a, b)
    fig = plt.figure(figsize=(0.01, 0.01))
    try:
        fig.text(0, 0, f"${s}$", fontsize=22)
        buf = io.BytesIO()
        fig.savefig(buf, dpi=100, bbox_inches="tight", pad_inches=0.05)
        im = Image.open(buf).convert("L")
    except Exception:
        im = Image.new("L", (900, 30), 255)
        ImageDraw.Draw(im).text((2, 2), "!! " + latex[:150], fill=0)
    finally:
        plt.close(fig)
    if im.height > height * 2:
        im = im.resize((int(im.width * height * 2 / im.height), height * 2))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", type=Path)
    ap.add_argument("--labels", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--per-sheet", type=int, default=8)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    cands = json.loads((a.dir / "candidates.json").read_text())
    rows = []
    for line in a.labels.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        idx, label = line.split("\t", 1)
        ink = render([np.asarray(p) for p in cands[int(idx)]["strokes"]], max_w=1000, target_h=70)
        tex = typeset(label.strip())
        w = 1150
        row = Image.new("L", (w, ink.height + tex.height + 26), 255)
        row.paste(ink, (40, 0))
        row.paste(tex.crop((0, 0, min(tex.width, w - 40), tex.height)), (40, ink.height + 2))
        d = ImageDraw.Draw(row)
        d.text((2, 2), idx, fill=0)
        d.text((40, ink.height + tex.height + 6), label.strip()[:170], fill=90)
        d.line([(0, row.height - 1), (w, row.height - 1)], fill=160)
        rows.append(row)
    for k in range(0, len(rows), a.per_sheet):
        chunk = rows[k:k + a.per_sheet]
        sheet = Image.new("L", (1150, sum(r.height for r in chunk)), 255)
        y = 0
        for r in chunk:
            sheet.paste(r, (0, y))
            y += r.height
        sheet.save(a.out / f"review{k // a.per_sheet:03d}.png")
    print(len(rows), "labels,", (len(rows) + a.per_sheet - 1) // a.per_sheet, "sheets")


if __name__ == "__main__":
    main()
