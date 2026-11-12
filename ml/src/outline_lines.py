"""Expression candidates from PDFs whose ink is stored as filled outlines (iPad apps).

Each filled path is one pen stroke drawn as its outline. It is rasterized on its
own, skeletonized, and the skeleton walked back into polylines, so stroke order
and pen lifts survive; only timing and direction are guessed. Grouping, guesses
and contact sheets are the same as user_lines.py.

    python src/outline_lines.py LECTURE_DIR OUT_DIR --checkpoint out/model/best.pt
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pymupdf
import torch
from PIL import Image, ImageDraw
from skimage.morphology import skeletonize

sys.path.insert(0, str(Path(__file__).parent))
import features as feat_mod  # noqa: E402
from evaluate import load  # noqa: E402
from user_lines import lines_of  # noqa: E402
from vocab import BOS_ID, EOS_ID, Vocab  # noqa: E402

DPI = 150
SPUR_PX = 14  # skeleton branches shorter than this are pen-tip artefacts
PX_PER_PT = 8  # skeleton resolution; a ~1 pt pen gives ~8 px wide outlines


def outline_polys(path):
    polys, cur = [], []
    for it in path["items"]:
        if it[0] == "l":
            seg = [it[1], it[2]]
        elif it[0] == "c":
            p0, p1, p2, p3 = it[1:5]
            seg = [p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t ** 2 * (1 - t) + p3 * t ** 3
                   for t in np.linspace(0, 1, 8)]
        elif it[0] == "re":
            r = it[1]
            seg = [r.tl, r.tr, r.br, r.bl, r.tl]
        else:
            continue
        if cur and abs(seg[0].x - cur[-1][0]) + abs(seg[0].y - cur[-1][1]) > 1e-3:
            polys.append(cur)
            cur = []
        cur += [(p.x, p.y) for p in seg]
    if cur:
        polys.append(cur)
    return [p for p in polys if len(p) >= 3]


def walk(skel):
    """Skeleton pixels -> polylines: from endpoints first, preferring straight continuation."""
    ys, xs = np.nonzero(skel)
    pix = set(zip(ys.tolist(), xs.tolist()))
    nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    def neigh(p):
        return [(p[0] + a, p[1] + b) for a, b in nb if (p[0] + a, p[1] + b) in pix]

    seen, out = set(), []
    while len(seen) < len(pix):
        left = [p for p in pix if p not in seen]
        ends = [p for p in left if sum(q not in seen for q in neigh(p)) <= 1]
        start = min(ends or left, key=lambda p: (p[1], p[0]))
        line, p, d = [start], start, None
        seen.add(start)
        while True:
            cand = [q for q in neigh(p) if q not in seen]
            if not cand:
                break
            if d is not None:
                cand.sort(key=lambda q: -((q[0] - p[0]) * d[0] + (q[1] - p[1]) * d[1]))
            q = cand[0]
            d = (q[0] - p[0], q[1] - p[1])
            seen.add(q)
            line.append(q)
            p = q
        if len(line) >= 4:
            out.append(np.array([(x, y) for y, x in line], dtype=np.float32))
    return out


def fill_strokes(path):
    polys = outline_polys(path)
    if not polys:
        return []
    allp = np.concatenate([np.array(p) for p in polys])
    lo = allp.min(0) - 1
    w, h = ((allp.max(0) + 1 - lo) * PX_PER_PT).astype(int) + 2
    if w * h > 4_000_000:
        return []
    img = Image.new("1", (int(w), int(h)), 0)
    dr = ImageDraw.Draw(img)
    for p in polys:
        dr.polygon([((x - lo[0]) * PX_PER_PT, (y - lo[1]) * PX_PER_PT) for x, y in p], fill=1)
    sk = skeletonize(np.pad(np.array(img.convert("L"), dtype=np.uint8) > 0, 2))[2:-2, 2:-2]
    s = DPI / 72
    res = []
    lines = walk(sk)
    longest = max((len(l) for l in lines), default=0)
    lines = [l for l in lines if len(l) >= SPUR_PX or len(l) == longest]
    for line in lines:
        pts = (line / PX_PER_PT + lo) * s
        keep = [0]
        for i in range(1, len(pts)):
            if np.hypot(*(pts[i] - pts[keep[-1]])) > 0.6:
                keep.append(i)
        if keep[-1] != len(pts) - 1:
            keep.append(len(pts) - 1)
        res.append(pts[keep])
    if not res:  # a dot: its centre
        c = (allp.mean(0)) * s
        res = [np.array([c, c + 0.3], dtype=np.float32)]
    return res


def is_ink(d, page_area):
    if d["type"] not in ("f", "fs") or d.get("fill") is None:
        return False
    if (d.get("fill_opacity") or 1) < 0.9:
        return False
    r = d["rect"]
    if r.width * r.height > page_area * 0.05:
        return False
    return sum(d["fill"]) / 3 < 0.75


def page_strokes(pdf, pno):
    doc = pymupdf.open(pdf)
    page = doc[pno]
    area = page.rect.width * page.rect.height
    strokes = []
    for d in page.get_drawings():
        if is_ink(d, area):
            strokes += fill_strokes(d)
    doc.close()
    return strokes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lectures", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--vocab", type=Path, default=Path("cache/vocab.json"))
    ap.add_argument("--per-sheet", type=int, default=10)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    model, cfg, _ = load(a.checkpoint, dev)
    vocab = Vocab.load(a.vocab)
    cands = []
    for pdf in sorted(a.lectures.glob("*.pdf"), key=lambda p: int("".join(c for c in p.stem if c.isdigit()) or 0)):
        for pno in range(len(pymupdf.open(pdf))):
            strokes = page_strokes(pdf, pno)
            if not strokes:
                continue
            groups, boxes = lines_of(strokes)
            for g in groups:
                x0 = min(boxes[i][0] for i in g); y0 = min(boxes[i][1] for i in g)
                x1 = max(boxes[i][2] for i in g); y1 = max(boxes[i][3] for i in g)
                if x1 - x0 < 30 or y1 - y0 > 140 or len(g) > 90:
                    continue
                ink = [strokes[i] for i in g]
                f = torch.from_numpy(feat_mod.extract(ink)).float()[None].to(dev)
                with torch.no_grad():
                    ids = model.greedy(f, torch.ones(f.shape[:2], dtype=torch.bool, device=dev), BOS_ID, EOS_ID)[0]
                guess = vocab.decode(ids.tolist() if hasattr(ids, "tolist") else ids)
                cands.append({"pdf": pdf.stem.replace(" ", "_"), "page": pno, "box": [float(x0), float(y0), float(x1), float(y1)],
                              "strokes": [s.round(2).tolist() for s in ink], "guess": guess})
        print(pdf.name, len(cands), flush=True)
    json.dump(cands, open(a.out / "candidates.json", "w"))
    sheets(a, cands)
    print(len(cands), "candidates")


def sheets(a, cands):
    """Two views per candidate: the PDF crop, and the traced strokes the model sees."""
    pages = {}
    for k in range(0, len(cands), a.per_sheet):
        rows = []
        for j, c in enumerate(cands[k:k + a.per_sheet]):
            key = (c["pdf"], c["page"])
            if key not in pages:
                src = a.lectures / (c["pdf"].replace("_", " ") + ".pdf")
                doc = pymupdf.open(src)
                pix = doc[c["page"]].get_pixmap(dpi=DPI)
                pages = {key: Image.frombytes("RGB", (pix.width, pix.height), pix.samples).convert("L")}
            x0, y0, x1, y1 = c["box"]
            crop = pages[key].crop((int(x0) - 6, int(y0) - 6, int(x1) + 6, int(y1) + 6))
            sc = min(1.0, 1100 / crop.width, 110 / crop.height) * 1.6
            sc = min(sc, 1100 / crop.width, 130 / crop.height)
            crop = crop.resize((max(1, int(crop.width * sc)), max(1, int(crop.height * sc))))
            row = Image.new("L", (1150, crop.height + 30), 255)
            row.paste(crop, (40, 0))
            d = ImageDraw.Draw(row)
            d.text((2, 2), str(k + j), fill=0)
            d.text((40, crop.height + 4), "guess: " + c["guess"][:160], fill=0)
            rows.append(row)
        sheet = Image.new("L", (1150, sum(r.height for r in rows)), 255)
        y = 0
        for r in rows:
            sheet.paste(r, (0, y)); y += r.height
        sheet.save(a.out / f"sheet{k // a.per_sheet:04d}.png")


if __name__ == "__main__":
    main()
