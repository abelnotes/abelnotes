"""Scores circuit_batch_test.dart output and renders the worst cases.

Per drawing, with U the typical part size:
  lost  - share of removed ink with no new ink within 0.45 U (a part or wire
          that vanished)
  wild  - share of new wire ink farther than 0.45 U from any drawn ink (a wire
          sent somewhere the user never drew)
  diag  - slanted segments in straightened wires (jogs, diagonals)
  error - the pipeline threw

    python batch_report.py BATCH_OUT_DIR REPORT_DIR [--worst 24]
"""
import argparse
import json
import pathlib

import numpy as np
from PIL import Image, ImageDraw
from scipy.spatial import cKDTree

SKIP = {"text", "junction", "terminal", "crossover", "gnd", "opamp", "ic"}


def dense(pts, step=1.0):
    pts = np.asarray(pts, float)
    if len(pts) < 2:
        return pts.reshape(-1, 2)
    out = [pts[:1]]
    for a, b in zip(pts[:-1], pts[1:]):
        n = max(1, int(np.ceil(np.linalg.norm(b - a) / step)))
        t = np.arange(1, n + 1)[:, None] / n
        out.append(a + (b - a) * t)
    return np.concatenate(out)


def score(r):
    if "error" in r:
        return {"name": r["name"], "error": 1, "ms": r["ms"]}
    sizes = sorted(max(d[4] - d[2], d[5] - d[3]) for d in r["dets"] if d[0] not in SKIP)
    unit = float(np.clip(sizes[len(sizes) // 2], 30, 90)) if sizes else 50.0
    removed = set(r["removed"])
    raw_all = [dense(s) for s in r["before"] if len(s)]
    raw_removed = [dense(r["before"][i]) for i in removed if len(r["before"][i])]
    new = [dense(a["pts"]) for a in r["added"] if len(a["pts"])]
    wires = [a for a in r["added"] if a.get("wire")]
    lost = wild = 0.0
    if raw_removed and new:
        tree = cKDTree(np.concatenate(new))
        d, _ = tree.query(np.concatenate(raw_removed))
        lost = float((d > 0.45 * unit).mean())
    elif raw_removed:
        lost = 1.0
    if wires and raw_all:
        tree = cKDTree(np.concatenate(raw_all))
        d, _ = tree.query(np.concatenate([dense(w["pts"]) for w in wires]))
        wild = float((d > 0.45 * unit).mean())
    diag = 0
    for w in wires:
        p = np.asarray(w["pts"])
        for a, b in zip(p[:-1], p[1:]):
            dx, dy = abs(b[0] - a[0]), abs(b[1] - a[1])
            if min(dx, dy) > 1.5 and np.hypot(dx, dy) > 3:
                diag += 1
    comps = sum(1 for d in r["dets"] if d[0] not in {"text", "junction", "terminal", "crossover"})
    return {"name": r["name"], "error": 0, "ms": r["ms"], "unit": round(unit), "comps": comps,
            "removed": len(removed), "of": len(r["before"]), "lost": round(lost, 3),
            "wild": round(wild, 3), "diag": diag}


def render(r, path, scale=1.0):
    w, h = int(r["w"] * scale), int(r["h"] * scale)
    im = Image.new("RGB", (2 * w + 10, h), "white")
    d = ImageDraw.Draw(im)
    for c, s, x0, y0, x1, y1 in r["dets"]:
        d.rectangle([x0 * scale, y0 * scale, x1 * scale, y1 * scale], outline=(0, 160, 0))
        d.text((x0 * scale + 2, y0 * scale + 1), c.split(".")[-1], fill=(0, 140, 0))
    for s in r["before"]:
        if len(s) > 1:
            d.line([(x * scale, y * scale) for x, y in s], fill="black", width=2)
    removed = set(r["removed"])
    for i, s in enumerate(r["before"]):
        if i not in removed and len(s) > 1:
            d.line([(x * scale + w + 10, y * scale) for x, y in s], fill="black", width=2)
    for a in r["added"]:
        if len(a["pts"]) > 1:
            d.line([(x * scale + w + 10, y * scale) for x, y in a["pts"]], fill=(220, 0, 0), width=2)
    im.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("batch", type=pathlib.Path)
    ap.add_argument("report", type=pathlib.Path)
    ap.add_argument("--worst", type=int, default=24)
    a = ap.parse_args()
    a.report.mkdir(parents=True, exist_ok=True)
    recs = {p.stem: json.loads(p.read_text()) for p in sorted(a.batch.glob("*.json"))}
    rows = [score(r) for r in recs.values()]
    ok = [x for x in rows if not x["error"]]
    print(f"{len(rows)} drawings, {len(rows) - len(ok)} errors")
    if ok:
        for k in ("lost", "wild", "diag", "ms"):
            v = np.array([x[k] for x in ok], float)
            print(f"  {k:5s} mean {v.mean():.3f}  p90 {np.percentile(v, 90):.3f}  max {v.max():.3f}")
    bad = sorted(ok, key=lambda x: -(x["lost"] * 3 + x["wild"] * 3 + x["diag"] * 0.02))
    (a.report / "scores.json").write_text(json.dumps(rows, indent=1))
    for x in bad[: a.worst]:
        print(f"  {x['name']:28s} lost {x['lost']:.2f} wild {x['wild']:.2f} diag {x['diag']:3d} "
              f"comps {x['comps']:2d} removed {x['removed']}/{x['of']} {x['ms']}ms")
        render(recs[x["name"]], a.report / f"{x['name']}.png", 0.6)
    for x in rows:
        if x["error"]:
            print("  ERROR", x["name"], recs[x["name"]]["error"].splitlines()[0])


if __name__ == "__main__":
    main()
