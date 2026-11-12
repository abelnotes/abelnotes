"""Cut every circuit out of vector PDFs of notes as a stroke fixture.

Pages are rendered so the page width maps to 1024 px, the scale at which the
app rasterizes a lasso selection; the detector runs on the whole page, its
part boxes are grown and merged into circuit regions, and the strokes inside
each region are written in page units, as the app would hand them over.

    python notes_circuits.py PDF_DIR OUT_DIR --weights best.pt
"""
import argparse
import json
import pathlib

import cv2
import numpy as np
import pymupdf
from ultralytics import YOLO

from extract_pdf_ink import ink_page
from wires import page_strokes

PARTS_ONLY = {"text", "junction", "terminal", "crossover"}


def regions(boxes, grow):
    """Merge boxes grown by [grow] into connected regions."""
    rs = [list(b) for b in boxes]
    merged = True
    while merged:
        merged = False
        for i in range(len(rs)):
            for j in range(i + 1, len(rs)):
                a, b = rs[i], rs[j]
                if (a[0] - grow < b[2] + grow and b[0] - grow < a[2] + grow
                        and a[1] - grow < b[3] + grow and b[1] - grow < a[3] + grow):
                    rs[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]), a[4] + b[4]]
                    del rs[j]
                    merged = True
                    break
            if merged:
                break
    return rs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdfs", type=pathlib.Path)
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("--weights", required=True)
    ap.add_argument("--min-parts", type=int, default=3)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    model = YOLO(a.weights)
    names = model.names
    n_out = 0
    for pdf in sorted(a.pdfs.glob("*.pdf")):
        doc = pymupdf.open(pdf)
        for pno in range(len(doc)):
            page = doc[pno]
            dpi = 1024 / page.rect.width * 72
            pix = ink_page(page, dpi, keep_color=False)
            img = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, pix.n)[..., :3]
            img = np.ascontiguousarray(img)
            res = model.predict(img, imgsz=max(img.shape[:2]) // 32 * 32 + 32, conf=0.3, device="cpu",
                                verbose=False)[0]
            boxes = []
            for (x0, y0, x1, y1), c in zip(res.boxes.xyxy.tolist(), res.boxes.cls.tolist()):
                if names[int(c)] not in PARTS_ONLY:
                    boxes.append((x0, y0, x1, y1, 1))
            if len(boxes) < a.min_parts:
                continue
            unit = float(np.median([max(b[2] - b[0], b[3] - b[1]) for b in boxes]))
            strokes = page_strokes(pdf, pno, dpi)
            for k, (x0, y0, x1, y1, n) in enumerate(regions(boxes, 1.2 * unit)):
                if n < a.min_parts:
                    continue
                pad = 0.8 * unit
                x0, y0, x1, y1 = x0 - pad, y0 - pad, x1 + pad, y1 + pad
                inside = []
                for s in strokes:
                    m = (s[:, 0] >= x0) & (s[:, 0] <= x1) & (s[:, 1] >= y0) & (s[:, 1] <= y1)
                    if m.mean() > 0.5:
                        inside.append((s * 72 / dpi).round(2).reshape(-1).tolist())
                name = f"{pdf.stem.replace(' ', '_')}_p{pno + 1}_{k}"
                (a.out / f"{name}.json").write_text(json.dumps({"pageWidth": page.rect.width, "strokes": inside}))
                n_out += 1
                print(name, n, "parts", len(inside), "strokes", flush=True)
    print(n_out, "circuits")


if __name__ == "__main__":
    main()
