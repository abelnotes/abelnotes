"""Digitize-HCD scans -> binarized ink images + YOLO labels in the v2 classes.

Digitize-HCD (Mendeley rngcz5wtv8, CC BY 4.0): 1,277 scans by 150+ drafters,
17 COCO classes plus text boxes. Benchmark data for image_bench.py: the shipped
model is not trained on it. Classes it does not annotate (junctions, terminals,
switches, batteries...) are pseudo-labelled by the current detector.
"""
import argparse
import json
import pathlib
import random

import cv2
from ultralytics import YOLO

from build_v2 import CLASSES, iou, write_labels
from prep_cghd import binarize

# Digitize-HCD name -> v2 class. Unlisted (V-DC one-port, a VDD arrow) stays background.
CLASS_MAP = {
    "BJT-NPN": "transistor.bjt", "BJT-PNP": "transistor.bjt",
    "Capacitor": "capacitor", "Diode": "diode", "Zener Diode": "diode",
    "GND": "gnd", "I-AC": "current_source", "I-DC": "current_source",
    "Inductor": "inductor", "MOSFET-N": "transistor.fet", "MOSFET-P": "transistor.fet",
    "Op-Amp": "opamp", "Resistor": "resistor", "V-AC": "voltage.ac", "V-DC": "voltage.dc",
    "Wire Crossover": "crossover",
}
PSEUDO = {"junction", "terminal", "switch", "voltage.battery", "vss", "ic",
          "transformer", "capacitor.polarized"}
PSEUDO_CONF = 0.5
VAL_SHARE = 0.1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dhcd", type=pathlib.Path, required=True,
                    help="the 'Component Symbol and Text Label Data' folder")
    ap.add_argument("--weights", required=True, help="detector for pseudo-labels")
    ap.add_argument("--out", type=pathlib.Path, required=True)
    ap.add_argument("--long-side", type=int, default=1280)
    a = ap.parse_args()
    comp = json.loads((a.dhcd / "component_annotations.json").read_text())
    text = {t["file_name"]: t["instances"]
            for t in json.loads((a.dhcd / "text_annotations.json").read_text())["data_list"]}
    cats = {c["id"]: c["name"] for c in comp["categories"]}
    anns = {}
    for o in comp["annotations"]:
        anns.setdefault(o["image_id"], []).append(o)
    for sub in ("images", "labels"):
        for split in ("train", "val"):
            (a.out / sub / split).mkdir(parents=True, exist_ok=True)
    model = YOLO(a.weights)
    rng = random.Random(0)
    stats = {"train": 0, "val": 0, "pseudo": 0}
    for im in sorted(comp["images"], key=lambda i: i["file_name"]):
        img = cv2.imread(str(a.dhcd / "Circuit Diagram Images" / im["file_name"]),
                         cv2.IMREAD_COLOR | cv2.IMREAD_IGNORE_ORIENTATION)
        if img is None:
            continue
        bw, s = binarize(img, a.long_side)
        H, W = bw.shape
        boxes = []
        for o in anns.get(im["id"], []):
            cls = CLASS_MAP.get(cats[o["category_id"]])
            if cls:
                x, y, w, h = o["bbox"]
                boxes.append((CLASSES.index(cls), [x * s, y * s, (x + w) * s, (y + h) * s]))
        for t in text.get(im["file_name"], []):
            x0, y0, x1, y1 = t["bbox"]
            boxes.append((CLASSES.index("text"), [x0 * s, y0 * s, x1 * s, y1 * s]))
        r = model.predict(cv2.cvtColor(bw, cv2.COLOR_GRAY2BGR), imgsz=1024,
                          conf=PSEUDO_CONF, verbose=False)[0]
        for b, c in zip(r.boxes.xyxy.tolist(), r.boxes.cls.tolist()):
            name = model.names[int(c)]
            if name in PSEUDO and not any(iou(b, g) > 0.3 for _, g in boxes):
                boxes.append((CLASSES.index(name), b))
                stats["pseudo"] += 1
        rows = []
        for c, (x0, y0, x1, y1) in boxes:
            x0, x1 = max(0, x0), min(W, x1)
            y0, y1 = max(0, y0), min(H, y1)
            if x1 - x0 >= 2 and y1 - y0 >= 2:
                rows.append([c, (x0 + x1) / 2 / W, (y0 + y1) / 2 / H, (x1 - x0) / W, (y1 - y0) / H])
        split = "val" if rng.random() < VAL_SHARE else "train"
        stem = f"dhcd_{pathlib.Path(im['file_name']).stem}"
        cv2.imwrite(str(a.out / "images" / split / f"{stem}.png"), bw)
        write_labels(a.out / "labels" / split / f"{stem}.txt", rows)
        stats[split] += 1
    print(stats)


if __name__ == "__main__":
    main()
