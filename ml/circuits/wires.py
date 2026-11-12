"""Wire tracing from ink strokes: components (detector boxes) + strokes -> nets.

Prototype of the app-side step. Input is what the canvas has: stroke polylines.
Strokes outside component/text boxes are wires; they are cut at box borders,
merged into nets where they touch, and a net touching a component's box is
connected to that component on that side.
"""
import argparse
import json
import pathlib

import cv2
import numpy as np
import pymupdf

GRID_MAX_WIDTH = 0.6
NON_COMPONENT = {"text", "junction", "crossover", "terminal"}


def page_strokes(pdf, page_no, dpi):
    s = dpi / 72
    page = pymupdf.open(pdf)[page_no]
    strokes = []
    for d in page.get_drawings():
        if (d.get("width") or 0) < GRID_MAX_WIDTH:
            continue
        pts = []
        for it in d["items"]:
            if it[0] == "l":
                seg = [it[1], it[2]]
            elif it[0] == "c":
                p0, p1, p2, p3 = it[1:5]
                seg = [p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t ** 2 * (1 - t) + p3 * t ** 3
                       for t in np.linspace(0, 1, 6)]
            else:
                continue
            for p in seg:
                q = (p.x * s, p.y * s)
                if not pts or np.hypot(q[0] - pts[-1][0], q[1] - pts[-1][1]) > 0.5:
                    pts.append(q)
        if len(pts) >= 2:
            strokes.append(np.array(pts))
    return strokes


def inside(p, b, pad=0):
    return b[0] - pad <= p[0] <= b[2] + pad and b[1] - pad <= p[1] <= b[3] + pad


def side_of(p, b):
    cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
    dx, dy = (p[0] - cx) / max(1, b[2] - b[0]), (p[1] - cy) / max(1, b[3] - b[1])
    return ("E" if dx > 0 else "W") if abs(dx) > abs(dy) else ("S" if dy > 0 else "N")


class DSU:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, a):
        while self.p[a] != a:
            self.p[a] = self.p[self.p[a]]
            a = self.p[a]
        return a

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def along(pc, dist):
    """Point roughly `dist` px into the polyline from its first point."""
    acc = 0.0
    for k in range(1, len(pc)):
        acc += np.hypot(*(pc[k] - pc[k - 1]))
        if acc >= dist:
            return pc[k]
    return pc[-1]


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(np.dot(p - a, ab) / max(1e-9, np.dot(ab, ab)), 0, 1)
    return np.hypot(*(a + t * ab - p))


def trace(strokes, dets, tol=9.0):
    comps = [d for d in dets if d["cls"] not in NON_COMPONENT]
    texts = [d["box"] for d in dets if d["cls"] == "text"]
    junctions = [d["box"] for d in dets if d["cls"] == "junction"]
    terminals = [d["box"] for d in dets if d["cls"] == "terminal"]

    # 1. Cut strokes into wire pieces outside component and text boxes.
    pieces = []
    for st in strokes:
        if sum(any(inside(p, t) for t in texts) for p in st) > 0.5 * len(st):
            continue
        cur = []
        for p in st:
            if any(inside(p, c["box"]) for c in comps):
                if len(cur) >= 2:
                    pieces.append(np.array(cur))
                cur = []
            else:
                cur.append(p)
        if len(cur) >= 2:
            pieces.append(np.array(cur))
    pieces = [pc for pc in pieces if np.hypot(*(pc[-1] - pc[0])) > 4 or len(pc) > 6]

    # 2. Merge pieces that touch: endpoint near another piece (T or L joint).
    #    Only ends join, so wires crossing through each other stay apart.
    dsu = DSU(len(pieces))
    for i, a in enumerate(pieces):
        for end in (a[0], a[-1]):
            for j, b in enumerate(pieces):
                if i == j:
                    continue
                if min(seg_dist(end, b[k], b[k + 1]) for k in range(len(b) - 1)) <= tol:
                    dsu.union(i, j)
    # Two wire ends facing each other across a short gap (a port drawn as a
    # break, or a terminal circle drawn inside the wire stroke) are one wire.
    # Direction from 60 px back: a terminal "o" drawn at the very end of the
    # stroke would otherwise make the last few points point backwards.
    ends = [(i, pc[0], along(pc, 60)) for i, pc in enumerate(pieces)] + \
           [(i, pc[-1], along(pc[::-1], 60)) for i, pc in enumerate(pieces)]
    for i, e, ni in ends:
        di = e - ni
        for j, f, nj in ends:
            if j == i:
                continue
            g = f - e
            gap = np.hypot(*g)
            if gap > 35 or gap < 1:
                continue
            dj = f - nj
            if np.dot(di, g) > 0.8 * np.hypot(*di) * gap and np.dot(dj, -g) > 0.8 * np.hypot(*dj) * gap:
                dsu.union(i, j)
    # Junction dots and open terminals join every wire reaching them. Tiny
    # strokes (a drawn dot or "o") count as nodes even when undetected.
    small = []
    for i, pc in enumerate(pieces):
        span = pc.max(0) - pc.min(0)
        if max(span) <= 16 and min(span) >= 4:  # dot or "o", not a dash
            small.append(i)
            x0, y0 = pc.min(0); x1, y1 = pc.max(0)
            junctions = junctions + [[x0, y0, x1, y1]]
    for jb in junctions + terminals:
        hit = [i for i, pc in enumerate(pieces) if any(inside(p, jb, tol + 3) for p in (pc[0], pc[-1])) or any(inside(p, jb, 1) for p in pc)]
        for i in hit[1:]:
            dsu.union(hit[0], i)

    # A ground/supply symbol is a single node: wires ending on it are one net.
    for c in comps:
        if c["cls"] in ("gnd", "vss"):
            hit = [i for i, pc in enumerate(pieces) if any(inside(e, c["box"], tol + 2) for e in (pc[0], pc[-1]))]
            for i in hit[1:]:
                dsu.union(hit[0], i)
    # A wire stopping short of an open terminal, in line with it, reaches it.
    for i in small:
        cx, cy = pieces[i].mean(0)
        for j, pc in enumerate(pieces):
            if j == i:
                continue
            for e, nxt in ((pc[0], pc[min(3, len(pc) - 1)]), (pc[-1], pc[max(-4, -len(pc))])):
                dx, dy = e[0] - cx, e[1] - cy
                d = np.hypot(dx, dy)
                if d > 40:
                    continue
                horiz = abs(dy) < tol and abs(nxt[1] - e[1]) < abs(nxt[0] - e[0]) and np.sign(nxt[0] - e[0]) == np.sign(dx)
                vert = abs(dx) < tol and abs(nxt[0] - e[0]) < abs(nxt[1] - e[1]) and np.sign(nxt[1] - e[1]) == np.sign(dy)
                if horiz or vert:
                    dsu.union(i, j)

    # 3. Attach net ends to components (endpoint on/near a box border).
    pins = {}
    for i, pc in enumerate(pieces):
        for end in (pc[0], pc[-1]):
            for ci, c in enumerate(comps):
                if inside(end, c["box"], tol + 2):
                    pins.setdefault(ci, set()).add((dsu.find(i), side_of(end, c["box"])))
    nets = sorted({dsu.find(i) for i in range(len(pieces))})
    netid = {r: k for k, r in enumerate(nets)}
    netlist = []
    for ci, c in enumerate(comps):
        netlist.append({"cls": c["cls"], "box": c["box"],
                        "pins": sorted({(netid[n], s) for n, s in pins.get(ci, set())}, key=lambda x: x[1])})
    term_nets = []
    for tb in terminals:
        for i, pc in enumerate(pieces):
            if any(inside(p, tb, 4) for p in pc):
                term_nets.append((netid[dsu.find(i)], tb)); break
    return pieces, [netid[dsu.find(i)] for i in range(len(pieces))], netlist, term_nets


def render(img, pieces, net_of, netlist):
    rng = np.random.default_rng(1)
    colors = {n: tuple(int(c) for c in rng.integers(30, 220, 3)) for n in set(net_of)}
    out = cv2.cvtColor(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), cv2.COLOR_GRAY2BGR)
    out = (255 - (255 - out) * 0.25).astype(np.uint8)
    for pc, n in zip(pieces, net_of):
        cv2.polylines(out, [np.int32(pc)], False, colors[n], 4, cv2.LINE_AA)
    for c in netlist:
        x0, y0, x1, y1 = c["box"]
        cv2.rectangle(out, (x0, y0), (x1, y1), (0, 0, 0), 1)
        lbl = c["cls"].split(".")[-1][:6] + " " + ",".join(f"{n}{s}" for n, s in c["pins"])
        cv2.putText(out, lbl, (x0, max(10, y0 - 3)), 0, 0.42, (0, 0, 0), 1, cv2.LINE_AA)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf", type=pathlib.Path, required=True)
    ap.add_argument("--page", type=int, required=True, help="1-based")
    ap.add_argument("--dets", type=pathlib.Path, required=True)
    ap.add_argument("--image", type=pathlib.Path, required=True)
    ap.add_argument("--out", type=pathlib.Path, required=True)
    ap.add_argument("--dpi", type=int, default=150)
    a = ap.parse_args()
    key = f"{a.pdf.stem.split(' ')[0]}_p{a.page:02d}"
    dets = [d for d in json.loads(a.dets.read_text())[key] if d["conf"] >= 0.35]
    strokes = page_strokes(a.pdf, a.page - 1, a.dpi)
    pieces, net_of, netlist, terms = trace(strokes, dets)
    cv2.imwrite(str(a.out), render(cv2.imread(str(a.image)), pieces, net_of, netlist))
    for c in netlist:
        print(c["cls"], c["pins"])


if __name__ == "__main__":
    main()
