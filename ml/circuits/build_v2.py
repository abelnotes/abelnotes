"""Dataset v2: CGHD + synthetic current sources + tiled pages of notes.

CGHD has no current-source class. Synthetic ones are made from CGHD's own
hand-drawn voltage sources: the interior is erased and a jittered arrow (or a
diamond plus arrow) is drawn along the wire axis, so the ring and the scene
stay real. Note tiles carry hand-checked source labels plus high-confidence
pseudo-labels from an earlier detector for everything else.
"""
import argparse
import json
import pathlib
import random
import shutil

import cv2
import numpy as np

from prep_cghd import CLASSES as V1_CLASSES
from predict_pages import tiles

CLASSES = V1_CLASSES + ["current_source"]
CUR = CLASSES.index("current_source")
VDC = CLASSES.index("voltage.dc")
VOLT = {CLASSES.index(c) for c in ("voltage.dc", "voltage.ac")}
PSEUDO_CONF = 0.5


def read_labels(p):
    if not p.exists():
        return []
    return [[int(v[0])] + [float(x) for x in v[1:]] for v in (l.split() for l in p.read_text().splitlines()) if v]


def write_labels(p, rows):
    p.write_text("".join(f"{c} {x:.6f} {y:.6f} {w:.6f} {h:.6f}\n" for c, x, y, w, h in rows))


def stroke_width(bw):
    ink = (bw < 128).astype(np.uint8)
    if ink.sum() == 0:
        return 3
    d = cv2.distanceTransform(ink, cv2.DIST_L2, 3)
    ridge = d[(d > 0) & (d >= cv2.dilate(d, np.ones((3, 3))))]
    return max(2, int(round(2 * np.median(ridge))))


def jitter_line(img, p0, p1, w, rng):
    n = 8
    pts = []
    nx, ny = p1[1] - p0[1], p0[0] - p1[0]
    norm = max(1e-6, np.hypot(nx, ny))
    amp = 0.03 * np.hypot(*(np.subtract(p1, p0)))
    for i in range(n + 1):
        t = i / n
        o = rng.normal(0, amp) * np.sin(np.pi * t)
        pts.append((p0[0] + (p1[0] - p0[0]) * t + o * nx / norm,
                    p0[1] + (p1[1] - p0[1]) * t + o * ny / norm))
    cv2.polylines(img, [np.int32(pts)], False, 0, w, cv2.LINE_AA)


def draw_arrow(img, c, r, axis, w, rng):
    s = rng.choice([-1, 1])
    if axis == "v":
        a, b = (c[0], c[1] - s * 0.6 * r), (c[0], c[1] + s * 0.6 * r)
    else:
        a, b = (c[0] - s * 0.6 * r, c[1]), (c[0] + s * 0.6 * r, c[1])
    a = (a[0] + rng.normal(0, 0.05 * r), a[1] + rng.normal(0, 0.05 * r))
    jitter_line(img, a, b, w, rng)
    ang = np.arctan2(b[1] - a[1], b[0] - a[0])
    hl = r * rng.uniform(0.3, 0.45)
    for da in (np.pi * 0.8, -np.pi * 0.8):
        da += rng.normal(0, 0.12)
        jitter_line(img, b, (b[0] + hl * np.cos(ang + da), b[1] + hl * np.sin(ang + da)), w, rng)
    if rng.random() < 0.3:  # filled head, as in some drawings
        tip = np.int32([b, (b[0] + hl * np.cos(ang + 2.6), b[1] + hl * np.sin(ang + 2.6)),
                        (b[0] + hl * np.cos(ang - 2.6), b[1] + hl * np.sin(ang - 2.6))])
        cv2.fillPoly(img, [tip], 0, cv2.LINE_AA)


def ring_ink(bw, c, w, h):
    """Fraction of angular sectors with ink on the box's outer annulus."""
    hits = 0
    for t in np.linspace(0, 2 * np.pi, 24, endpoint=False):
        found = False
        for f in np.linspace(0.68, 1.0, 6):
            px = int(c[0] + f * w / 2 * np.cos(t)); py = int(c[1] + f * h / 2 * np.sin(t))
            if 0 <= py < bw.shape[0] and 0 <= px < bw.shape[1] and bw[py, px] < 128:
                found = True; break
        hits += found
    return hits / 24


def wire_axis(bw, x0, y0, x1, y1):
    h, w = bw.shape
    m = max(3, int(0.15 * max(x1 - x0, y1 - y0)))
    def ink(ya, yb, xa, xb):
        ya, yb, xa, xb = max(0, ya), min(h, yb), max(0, xa), min(w, xb)
        return 0 if ya >= yb or xa >= xb else (bw[ya:yb, xa:xb] < 128).mean()
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    q = max(2, (x1 - x0) // 6)
    vert = ink(y0 - m, y0, cx - q, cx + q) + ink(y1, y1 + m, cx - q, cx + q)
    q = max(2, (y1 - y0) // 6)
    horz = ink(cy - q, cy + q, x0 - m, x0) + ink(cy - q, cy + q, x1, x1 + m)
    return "v" if vert >= horz else "h"


def synth_current(src_img, src_lbl, dst_img, dst_lbl, rng):
    bw = cv2.imread(str(src_img), 0)
    H, W = bw.shape
    rows = read_labels(src_lbl)
    if not any(r[0] in VOLT for r in rows):
        return False
    sw = stroke_width(bw)
    out = []
    for c, x, y, w, h in rows:
        if c not in VOLT or rng.random() < 0.15:
            out.append([c, x, y, w, h]); continue
        x0, y0, x1, y1 = int((x - w / 2) * W), int((y - h / 2) * H), int((x + w / 2) * W), int((y + h / 2) * H)
        cxy = ((x0 + x1) / 2, (y0 + y1) / 2)
        if ring_ink(bw, cxy, x1 - x0, y1 - y0) < 0.5:
            out.append([c, x, y, w, h]); continue
        axis = wire_axis(bw, x0, y0, x1, y1)
        r = 0.5 * min(x1 - x0, y1 - y0)
        # Drop any labels (text, junction) that sat inside the erased area.
        out = [o for o in out if not (abs(o[1] - x) < w / 2 and abs(o[2] - y) < h / 2 and o[0] not in VOLT)]
        if rng.random() < 0.25:  # dependent source: diamond
            cv2.rectangle(bw, (x0, y0), (x1, y1), 255, -1)
            d = [(cxy[0], y0), (x1, cxy[1]), (cxy[0], y1), (x0, cxy[1])]
            for i in range(4):
                jitter_line(bw, d[i], d[(i + 1) % 4], sw, rng)
        else:
            cv2.ellipse(bw, (int(cxy[0]), int(cxy[1])), (int(0.62 * (x1 - x0) / 2), int(0.62 * (y1 - y0) / 2)),
                        0, 0, 360, 255, -1)
        draw_arrow(bw, cxy, r, axis, sw, rng)
        out.append([CUR, x, y, w, h])
    cv2.imwrite(str(dst_img), bw)
    write_labels(dst_lbl, out)
    return True


def iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0])); iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    i = ix * iy
    return i / max(1e-6, (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i)


def note_tiles(pages_dir, dets, src_labels, test_pages, out, rng):
    by_page = {}
    for kind, box, page in src_labels:
        by_page.setdefault(page, []).append((kind, box))
    stats = {"train": 0, "test": 0}
    for page, ds in sorted(dets.items()):
        split = "test" if page.startswith(test_pages) else "train"
        img = cv2.imread(str(pages_dir / f"{page}.png"), 0)
        H, W = img.shape
        hand = [(CUR if k == "I" else VDC, b) for k, b in by_page.get(page, [])]
        boxes = list(hand)
        for d in ds:
            if d["conf"] < PSEUDO_CONF or d["cls"] not in V1_CLASSES:
                continue
            c = CLASSES.index(d["cls"])
            if c in VOLT or c == CLASSES.index("voltage.battery"):
                continue
            if any(iou(d["box"], b) > 0.3 for _, b in hand):
                continue
            boxes.append((c, d["box"]))
        for k, (ty0, ty1) in enumerate(tiles(H, W)):
            inside = []
            for c, (x0, y0, x1, y1) in boxes:
                cy = (y0 + y1) / 2
                if not ty0 <= cy < ty1:
                    continue
                y0c, y1c = max(y0, ty0), min(y1, ty1)
                if (y1c - y0c) < 0.6 * (y1 - y0):
                    continue
                th = ty1 - ty0
                inside.append([c, (x0 + x1) / 2 / W, ((y0c + y1c) / 2 - ty0) / th, (x1 - x0) / W, (y1c - y0c) / th])
            comps = [r for r in inside if r[0] not in (CLASSES.index("text"),)]
            if not comps and rng.random() > 0.15:
                continue
            stem = f"notes_{page}_t{k}"
            cv2.imwrite(str(out / "images" / split / f"{stem}.png"), img[ty0:ty1])
            write_labels(out / "labels" / split / f"{stem}.txt", inside)
            stats[split] += 1
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--v1", type=pathlib.Path, required=True)
    ap.add_argument("--pages", type=pathlib.Path, required=True)
    ap.add_argument("--dets", type=pathlib.Path, required=True)
    ap.add_argument("--cands", type=pathlib.Path, required=True)
    ap.add_argument("--hand-labels", type=pathlib.Path, required=True)
    ap.add_argument("--test-pages", nargs="*", default=[],
                    help="page name prefixes held out as test, whole documents")
    ap.add_argument("--out", type=pathlib.Path, required=True)
    a = ap.parse_args()
    rng = np.random.default_rng(0)
    random.seed(0)
    for split in ("train", "val", "test"):
        for sub in ("images", "labels"):
            (a.out / sub / split).mkdir(parents=True, exist_ok=True)
    for split in ("train", "val"):
        for p in (a.v1 / "images" / split).glob("*.png"):
            dst = a.out / "images" / split / p.name
            if not dst.exists():
                dst.symlink_to(p)
            shutil.copy(a.v1 / "labels" / split / f"{p.stem}.txt", a.out / "labels" / split / f"{p.stem}.txt")
    n_syn = {"train": 0, "val": 0}
    for split in ("train", "val"):
        for p in sorted((a.v1 / "images" / split).glob("*.png")):
            if synth_current(p, a.v1 / "labels" / split / f"{p.stem}.txt",
                             a.out / "images" / split / f"syn_{p.stem}.png",
                             a.out / "labels" / split / f"syn_{p.stem}.txt", rng):
                n_syn[split] += 1
    cands = json.loads(a.cands.read_text())
    hand = []
    for line in a.hand_labels.read_text().splitlines():
        kind, *ids = line.split()
        hand += [(kind, cands[int(i)][3], cands[int(i)][0]) for i in ids]
    notes = note_tiles(a.pages, json.loads(a.dets.read_text()), hand, tuple(a.test_pages), a.out, rng)
    (a.out / "data.yaml").write_text(
        f"path: {a.out}\ntrain: images/train\nval: images/val\ntest: images/test\n"
        f"names: {json.dumps(CLASSES)}\n")
    print("synthetic:", n_syn, "note tiles:", notes)


if __name__ == "__main__":
    main()
