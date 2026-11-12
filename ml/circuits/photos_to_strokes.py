"""Hand-drawn circuit photos -> stroke fixtures for the Dart pipeline tests.

Binarizes like prep_cghd.py, thins the ink to a one-pixel skeleton and traces
it into polylines, so a photo can stand in for strokes drawn in the app. The
fixture's pageWidth is 1024, so the app rasterizes it back at the scale the
detector was trained on.

    python photos_to_strokes.py --cghd CGHD_DIR \
        --drafters drafter_3 drafter_17 --out photo_fixtures
"""
import argparse
import json
import pathlib

import cv2
import numpy as np

from prep_cghd import binarize

# 8-neighbourhood, clockwise from north (Zhang-Suen order).
NB = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)]


def thin(ink):
    """Zhang-Suen thinning of a bool image."""
    img = np.pad(ink.astype(np.uint8), 1)
    while True:
        changed = False
        for step in (0, 1):
            p = [np.roll(np.roll(img, -dy, 0), -dx, 1) for dy, dx in NB]
            b = sum(p)
            a = sum(((p[k] == 0) & (p[(k + 1) % 8] == 1)).astype(np.uint8) for k in range(8))
            if step == 0:
                c1, c2 = p[0] * p[2] * p[4], p[2] * p[4] * p[6]
            else:
                c1, c2 = p[0] * p[2] * p[6], p[0] * p[4] * p[6]
            kill = (img == 1) & (b >= 2) & (b <= 6) & (a == 1) & (c1 == 0) & (c2 == 0)
            if kill.any():
                img[kill] = 0
                changed = True
        if not changed:
            return img[1:-1, 1:-1].astype(bool)


def _groups(ring):
    """Connected groups among the set positions of a 3x3 ring (NB order)."""
    on = [k for k in range(8) if ring[k]]
    seen, n = set(), 0
    for k in on:
        if k in seen:
            continue
        n += 1
        stack = [k]
        while stack:
            i = stack.pop()
            if i in seen:
                continue
            seen.add(i)
            for j in on:
                d = (i - j) % 8
                if j not in seen and (d in (1, 7) or (d in (2, 6) and i % 2 == 0 and j % 2 == 0)):
                    stack.append(j)
    return n


def unstair(skel):
    """Drop skeleton pixels whose removal keeps their neighbours connected
    (staircase corners), so plain runs have exactly two neighbours."""
    sk = np.pad(skel, 1).copy()
    changed = True
    while changed:
        changed = False
        for y, x in zip(*np.nonzero(sk)):
            ring = [sk[y + dy, x + dx] for dy, dx in NB]
            if sum(ring) >= 2 and _groups(ring) == 1 and sum(ring) <= 4:
                sk[y, x] = False
                changed = True
    return sk[1:-1, 1:-1]


def trace(skel, min_spur=6):
    """Skeleton -> list of polylines [(x, y), ...], split at junctions."""
    h, w = skel.shape
    pix = set(zip(*np.nonzero(skel)))

    def nbrs(p):
        y, x = p
        return [(y + dy, x + dx) for dy, dx in NB if (y + dy, x + dx) in pix]

    deg = {p: len(nbrs(p)) for p in pix}
    nodes = {p for p, d in deg.items() if d != 2}
    used = set()
    paths = []
    for n in nodes:
        for q in nbrs(n):
            if (n, q) in used:
                continue
            path = [n, q]
            used.add((n, q))
            used.add((q, n))
            prev, cur = n, q
            while cur not in nodes:
                nxt = [r for r in nbrs(cur) if r != prev and (cur, r) not in used]
                if not nxt:
                    break
                used.add((cur, nxt[0]))
                used.add((nxt[0], cur))
                prev, cur = cur, nxt[0]
                path.append(cur)
            paths.append(path)
    # Closed loops with no junction (a ring drawn on its own).
    seen = {p for path in paths for p in path}
    for p in pix - seen:
        if p in seen or deg[p] != 2:
            continue
        path, prev, cur = [p], None, p
        while True:
            nxt = [r for r in nbrs(cur) if r != prev and r not in path[-3:]]
            if not nxt or nxt[0] in seen:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            path.append(cur)
        seen.add(p)
        if len(path) > 4:
            paths.append(path + [p])
    out = []
    for path in paths:
        ends_free = deg[path[0]] == 1 or deg[path[-1]] == 1
        if len(path) < min_spur and ends_free:
            continue  # thinning spur
        pts = np.array([(x, y) for y, x in path], np.float32).reshape(-1, 1, 2)
        simp = cv2.approxPolyDP(pts, 0.8, False).reshape(-1, 2)
        if len(simp) >= 2:
            out.append(simp.tolist())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cghd", type=pathlib.Path, required=True)
    ap.add_argument("--drafters", nargs="+", required=True)
    ap.add_argument("--out", type=pathlib.Path, required=True)
    ap.add_argument("--long-side", type=int, default=1280)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    photos = sorted(p for d in a.drafters for p in (a.cghd / d / "images").iterdir())
    if a.limit:
        photos = photos[: a.limit]
    for p in photos:
        img = cv2.imread(str(p), cv2.IMREAD_COLOR | cv2.IMREAD_IGNORE_ORIENTATION)
        if img is None:
            continue
        bw, _ = binarize(img, a.long_side)
        strokes = trace(unstair(thin(bw < 128)))
        flat = [[round(v, 1) for xy in s for v in xy] for s in strokes]
        name = f"{p.parent.parent.name}_{p.stem}"
        (a.out / f"{name}.json").write_text(json.dumps({"pageWidth": 1024, "strokes": flat}))
        print(name, len(flat), "strokes")


if __name__ == "__main__":
    main()
