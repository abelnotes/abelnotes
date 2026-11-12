"""Bench for the picture tidy-up (image_ink.dart): how many labelled parts
survive tracing a picture into strokes, against the detector run on the
picture itself.

    python image_bench.py prep --ml ML_DIR --out BENCH
    ABELNOTES_IMAGE_BENCH=BENCH/<set> ABELNOTES_IMAGE_BENCH_OUT=RUN/<set> \\
        flutter test test/circuit_image_bench_test.dart        # per set
    python image_bench.py eval --bench BENCH --run RUN --weights best.pt

Sets: cghd (phone photos of paper, held-out drafters 3 and 17), dhcd
(Digitize-HCD scans), notes (rendered pages of handwritten notes, notes_yolo
test), printed (CircuiTikZ schematics degraded like screenshots, counts
only). Each image has <stem>.gt.json: boxes in its pixels, or counts.
"""
import argparse
import json
import pathlib
import random

import cv2
import numpy as np

NAMES = ["capacitor", "capacitor.polarized", "crossover", "diode", "gnd", "ic", "inductor", "junction",
         "opamp", "resistor", "switch", "terminal", "text", "transformer", "transistor.bjt",
         "transistor.fet", "voltage.ac", "voltage.battery", "voltage.dc", "vss", "current_source", "arrow"]
NOT_PARTS = {"text", "junction", "terminal", "crossover", "arrow"}
LONG = 2000


def yolo_boxes(txt, w, h):
    out = []
    for line in pathlib.Path(txt).read_text().split("\n"):
        if not line.strip():
            continue
        c, cx, cy, bw, bh = line.split()
        cx, cy, bw, bh = float(cx) * w, float(cy) * h, float(bw) * w, float(bh) * h
        out.append([NAMES[int(c)], cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2])
    return out


def save(img, gt, out, stem):
    s = LONG / max(img.shape[:2])
    if s < 1:
        img = cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    h, w = img.shape[:2]
    boxes = [[c, x0 * w, y0 * h, x1 * w, y1 * h] for c, x0, y0, x1, y1 in gt]
    cv2.imwrite(str(out / f"{stem}.png"), img)
    (out / f"{stem}.gt.json").write_text(json.dumps({"boxes": boxes}))


def prep(a):
    data = a.ml / "data"
    rng = random.Random(0)
    norm = lambda bs, w, h: [[c, x0 / w, y0 / h, x1 / w, y1 / h] for c, x0, y0, x1, y1 in bs]
    # Phone photos: raw JPEGs, labels from cghd_yolo (normalised, same framing).
    out = a.out / "cghd"
    out.mkdir(parents=True, exist_ok=True)
    for drafter in ("drafter_3", "drafter_17"):
        photos = sorted((data / "cghd" / drafter / "images").iterdir())
        for p in rng.sample(photos, a.n // 2):
            lbl = data / "cghd_yolo" / "labels" / "val" / f"{drafter}_{p.stem}.txt"
            img = cv2.imread(str(p), cv2.IMREAD_COLOR | cv2.IMREAD_IGNORE_ORIENTATION)
            if img is None or not lbl.exists():
                continue
            h, w = img.shape[:2]
            save(img, norm(yolo_boxes(lbl, w, h), w, h), out, f"{drafter}_{p.stem}")
    # Scans: raw Digitize-HCD JPEGs, labels from dhcd_yolo val.
    out = a.out / "dhcd"
    out.mkdir(parents=True, exist_ok=True)
    raw = next((data / "digitize_hcd" / "raw").rglob("Circuit Diagram Images"))
    labels = sorted((data / "dhcd_yolo" / "labels" / "val").glob("*.txt"))
    for lbl in rng.sample(labels, a.n):
        img = cv2.imread(str(raw / f"{lbl.stem.removeprefix('dhcd_')}.jpg"), cv2.IMREAD_COLOR | cv2.IMREAD_IGNORE_ORIENTATION)
        if img is None:
            continue
        h, w = img.shape[:2]
        save(img, norm(yolo_boxes(lbl, w, h), w, h), out, lbl.stem)
    # Rendered notes, if there are any: pen on screen.
    out = a.out / "notes"
    out.mkdir(parents=True, exist_ok=True)
    imgs = sorted((data / "notes_yolo" / "images" / "test").glob("*.png"))
    for p in rng.sample(imgs, min(a.n, len(imgs))):
        img = cv2.imread(str(p))
        h, w = img.shape[:2]
        save(img, norm(yolo_boxes(data / "notes_yolo" / "labels" / "test" / f"{p.stem}.txt", w, h), w, h), out, p.stem)


def iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0


def match(gt, found, same_class):
    """Ground-truth parts found (IoU >= 0.3), greedy by IoU."""
    pairs = sorted(((iou(g[1:], f["box"]), i, j) for i, g in enumerate(gt) for j, f in enumerate(found)
                    if not same_class or g[0] == f["cls"]), reverse=True)
    used_g, used_f = set(), set()
    for v, i, j in pairs:
        if v < 0.3:
            break
        if i not in used_g and j not in used_f:
            used_g.add(i)
            used_f.add(j)
    return len(used_g), len(used_f)


def evaluate(a):
    from ultralytics import YOLO
    import sys
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    from prep_cghd import binarize
    model = YOLO(a.weights)
    rows = []
    for set_dir in sorted(p for p in a.bench.iterdir() if p.is_dir()):
        tot = {"gt": 0, "direct": 0, "direct_cls": 0, "traced": 0, "traced_cls": 0, "redrawn": 0,
               "redrawn_cls": 0, "redrawn_n": 0, "redrawn_ok": 0, "count_ok": 0, "count_gt": 0}
        per = []
        for gtf in sorted(set_dir.glob("*.gt.json")):
            stem = gtf.name[:-len(".gt.json")]
            run = a.run / set_dir.name / f"{stem}.json"
            if not run.exists():
                continue
            gt = json.loads(gtf.read_text())
            res = json.loads(run.read_text())
            dets = [d for d in res["dets"] if d["cls"] not in NOT_PARTS]
            comps = res["comps"]
            if "counts" in gt:
                want = gt["counts"]
                got = {}
                for c in comps:
                    got[c["cls"]] = got.get(c["cls"], 0) + 1
                tot["count_gt"] += sum(want.values())
                tot["count_ok"] += sum(min(v, got.get(k, 0)) for k, v in want.items())
                per.append((sum(min(v, got.get(k, 0)) for k, v in want.items()) / max(1, sum(want.values())), stem))
                continue
            parts = [b for b in gt["boxes"] if b[0] not in NOT_PARTS]
            img = cv2.imread(str(set_dir / f"{stem}.png"))
            bw, s = binarize(img, 1280)
            r = model.predict(cv2.cvtColor(bw, cv2.COLOR_GRAY2BGR), imgsz=1024, conf=0.3, verbose=False)[0]
            direct = [{"cls": model.names[int(c)], "box": [v / s for v in b]}
                      for b, c in zip(r.boxes.xyxy.tolist(), r.boxes.cls.tolist()) if model.names[int(c)] not in NOT_PARTS]
            tot["gt"] += len(parts)
            tot["direct"] += match(parts, direct, False)[0]
            tot["direct_cls"] += match(parts, direct, True)[0]
            tot["traced"] += match(parts, dets, False)[0]
            tot["traced_cls"] += match(parts, dets, True)[0]
            got, used = match(parts, comps, False)
            tot["redrawn"] += got
            tot["redrawn_cls"] += match(parts, comps, True)[0]
            tot["redrawn_n"] += len(comps)
            tot["redrawn_ok"] += match(parts, comps, True)[1]
            per.append((match(parts, comps, True)[0] / max(1, len(parts)), stem))
        if tot["count_gt"]:
            rows.append(f"{set_dir.name:8s} n={len(per):3d}  parts drawn {tot['count_gt']:4d}  "
                        f"redrawn right {tot['count_ok'] / tot['count_gt']:.2f}")
        elif tot["gt"]:
            g = tot["gt"]
            rows.append(f"{set_dir.name:8s} n={len(per):3d}  parts {g:4d}  found/right-class: "
                        f"on picture {tot['direct'] / g:.2f}/{tot['direct_cls'] / g:.2f}  "
                        f"on traced {tot['traced'] / g:.2f}/{tot['traced_cls'] / g:.2f}  "
                        f"redrawn {tot['redrawn'] / g:.2f}/{tot['redrawn_cls'] / g:.2f}  "
                        f"redraw precision {tot['redrawn_ok'] / max(1, tot['redrawn_n']):.2f}")
        worst = sorted(per)[:a.worst]
        (a.run / f"{set_dir.name}_worst.txt").write_text("\n".join(f"{v:.2f} {s}" for v, s in worst))
    print("\n".join(rows))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prep")
    p.add_argument("--ml", type=pathlib.Path, required=True)
    p.add_argument("--out", type=pathlib.Path, required=True)
    p.add_argument("--n", type=int, default=30)
    e = sub.add_parser("eval")
    e.add_argument("--bench", type=pathlib.Path, required=True)
    e.add_argument("--run", type=pathlib.Path, required=True)
    e.add_argument("--weights", required=True)
    e.add_argument("--worst", type=int, default=6)
    a = ap.parse_args()
    prep(a) if a.cmd == "prep" else evaluate(a)
