"""Render only the handwritten ink of vector PDFs exported by note-taking apps.

Drops the ruled/squared paper so pages look like what the app rasterizes from
a lasso selection: dark strokes on white.
"""
import argparse
import pathlib

import pymupdf

GRID_MAX_WIDTH = 0.6  # paper lines are ~0.36-0.55 pt, ink is ~1.2 pt
HIGHLIGHTER_MIN_WIDTH = 8.0


def ink_page(page, dpi, keep_color, width_scale=1.0):
    scale = dpi / 72
    out = pymupdf.open()
    dst = out.new_page(width=page.rect.width, height=page.rect.height)
    shape = dst.new_shape()
    for d in page.get_drawings():
        fill = d.get("fill")
        # Some apps export ink as filled outlines, others as stroked centerlines.
        # Translucent fills are highlighter: opaque, they black out the text under them.
        is_ink_fill = fill is not None and sum(fill) / 3 < 0.7 and d.get("fill_opacity", 1) >= 0.5
        if not is_ink_fill and not (GRID_MAX_WIDTH <= (d.get("width") or 0) < HIGHLIGHTER_MIN_WIDTH):
            continue
        for item in d["items"]:
            op = item[0]
            if op == "l":
                shape.draw_line(item[1], item[2])
            elif op == "c":
                shape.draw_bezier(item[1], item[2], item[3], item[4])
            elif op == "re":
                shape.draw_rect(item[1])
            elif op == "qu":
                shape.draw_quad(item[1])
        if is_ink_fill:
            color = fill if keep_color else (0, 0, 0)
            shape.finish(color=color, fill=color, width=0.6 * (width_scale - 1) + 0.01,
                         closePath=True, lineCap=1, lineJoin=1)
            continue
        color = d.get("color") if keep_color else (0, 0, 0)
        shape.finish(color=color, width=(d.get("width") or 1.2) * width_scale,
                     closePath=False, lineCap=1, lineJoin=1)
    shape.commit()
    return dst.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdfs", nargs="+", type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path, required=True)
    ap.add_argument("--dpi", type=int, default=100)
    ap.add_argument("--color", action="store_true")
    ap.add_argument("--width-scale", type=float, default=1.0)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    for pdf in a.pdfs:
        doc = pymupdf.open(pdf)
        stem = pdf.stem.split(" 0")[0].replace(" ", "")
        for i, page in enumerate(doc):
            ink_page(page, a.dpi, a.color, a.width_scale).save(a.out / f"{stem}_p{i + 1:02d}.png")


if __name__ == "__main__":
    main()
