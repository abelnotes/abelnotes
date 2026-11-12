"""Cut handwritten lecture pages into expression candidates and propose LaTeX.

Strokes are grouped into lines by vertical overlap, lines are split at wide
horizontal gaps, and each piece gets the current model's greedy guess. The
output is a contact sheet per batch plus a JSON of candidates; a human then
corrects the guesses (labels.tsv) for fine-tuning on that person's writing.

    python src/user_lines.py LECTURE_DIR OUT_DIR --checkpoint out/model/best.pt
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "circuits"))
import features as feat_mod  # noqa: E402
from evaluate import load  # noqa: E402
from vocab import BOS_ID, EOS_ID, Vocab  # noqa: E402
from wires import page_strokes  # noqa: E402

DPI = 150


def lines_of(strokes):
    boxes = [(s[:, 0].min(), s[:, 1].min(), s[:, 0].max(), s[:, 1].max()) for s in strokes]
    order = sorted(range(len(strokes)), key=lambda i: (boxes[i][1] + boxes[i][3]) / 2)
    groups = []
    for i in order:
        y0, y1 = boxes[i][1], boxes[i][3]
        cy = (y0 + y1) / 2
        for g in groups:
            if g["y0"] - 8 <= cy <= g["y1"] + 8 and (y1 - y0) < 120:
                g["ids"].append(i)
                g["y0"], g["y1"] = min(g["y0"], y0), max(g["y1"], y1)
                break
        else:
            groups.append({"ids": [i], "y0": y0, "y1": y1})
    out = []
    for g in groups:
        ids = sorted(g["ids"], key=lambda i: boxes[i][0])
        cur, right = [], -1e9
        for i in ids:
            if cur and boxes[i][0] - right > 70:
                out.append(cur)
                cur = []
            cur.append(i)
            right = max(right, boxes[i][2])
        out.append(cur)
    return [o for o in out if len(o) >= 3], boxes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lectures", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--vocab", type=Path, default=Path("cache/vocab.json"))
    ap.add_argument("--per-sheet", type=int, default=10)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    model, cfg, _ = load(a.checkpoint, "cpu")
    vocab = Vocab.load(a.vocab)
    cands = []
    for pdf in sorted(a.lectures.glob("*.pdf")):
        import pymupdf
        for pno in range(len(pymupdf.open(pdf))):
            strokes = page_strokes(pdf, pno, DPI)
            if not strokes:
                continue
            groups, boxes = lines_of(strokes)
            for g in groups:
                x0 = min(boxes[i][0] for i in g); y0 = min(boxes[i][1] for i in g)
                x1 = max(boxes[i][2] for i in g); y1 = max(boxes[i][3] for i in g)
                if x1 - x0 < 60:
                    continue
                ink = [strokes[i] for i in g]
                f = torch.from_numpy(feat_mod.extract(ink)).float()[None]
                with torch.no_grad():
                    ids = model.greedy(f, torch.ones(f.shape[:2], dtype=torch.bool), BOS_ID, EOS_ID)[0]
                guess = vocab.decode(ids.tolist() if hasattr(ids, "tolist") else ids)
                cands.append({"pdf": pdf.name, "page": pno, "box": [float(x0), float(y0), float(x1), float(y1)],
                              "strokes": [s.round(2).tolist() for s in ink], "guess": guess})
    json.dump(cands, open(a.out / "candidates.json", "w"))
    pages = {}
    for k in range(0, len(cands), a.per_sheet):
        rows = []
        for j, c in enumerate(cands[k:k + a.per_sheet]):
            key = (c["pdf"], c["page"])
            if key not in pages:
                pages = {key: Image.open(render(a, c["pdf"], c["page"]))}
            x0, y0, x1, y1 = c["box"]
            crop = pages[key].crop((int(x0) - 6, int(y0) - 6, int(x1) + 6, int(y1) + 6))
            crop.thumbnail((1100, 110))
            row = Image.new("L", (1150, crop.height + 30), 255)
            row.paste(crop, (40, 0))
            d = ImageDraw.Draw(row)
            d.text((2, 2), str(k + j), fill=0)
            d.text((40, crop.height + 4), c["guess"][:170], fill=0)
            rows.append(row)
        sheet = Image.new("L", (1150, sum(r.height for r in rows)), 255)
        y = 0
        for r in rows:
            sheet.paste(r, (0, y)); y += r.height
        sheet.save(a.out / f"sheet{k // a.per_sheet:03d}.png")
    print(len(cands), "candidates")


def render(a, pdf_name, pno):
    path = a.out / f"page_{Path(pdf_name).stem.replace(' ', '_')}_{pno}.png"
    if not path.exists():
        import pymupdf
        pix = pymupdf.open(a.lectures / pdf_name)[pno].get_pixmap(dpi=DPI)
        pix.save(path)
    return path


if __name__ == "__main__":
    main()
