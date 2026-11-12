"""Run the detector over rendered pages of notes in overlapping half-page tiles.

Tiles keep symbols at roughly the scale the detector was trained on; detections
from overlapping tiles are merged with NMS in page coordinates.
"""
import argparse
import json
import pathlib

import cv2
import numpy as np
import torch
import torchvision
from ultralytics import YOLO


def tiles(h, w, n=3, overlap=0.35):
    th = int(h / (n - (n - 1) * overlap))
    step = int(th * (1 - overlap))
    ys = list(range(0, max(1, h - th) + 1, max(1, step)))
    if ys[-1] + th < h:
        ys.append(h - th)
    return [(y, min(h, y + th)) for y in ys]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", required=True)
    ap.add_argument("--pages", type=pathlib.Path, required=True)
    ap.add_argument("--out", type=pathlib.Path, required=True)
    ap.add_argument("--conf", type=float, default=0.35)
    ap.add_argument("--glob", default="*.png")
    ap.add_argument("--device", default=None)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    model = YOLO(a.weights)
    names = model.names
    summary = {}
    for p in sorted(a.pages.glob(a.glob)):
        img = cv2.imread(str(p))
        h, w = img.shape[:2]
        boxes, scores, cls = [], [], []
        for y0, y1 in tiles(h, w):
            r = model.predict(img[y0:y1], imgsz=1024, conf=a.conf, device=a.device, verbose=False)[0]
            b = r.boxes.xyxy.cpu().numpy()
            b[:, [1, 3]] += y0
            boxes.append(b); scores.append(r.boxes.conf.cpu().numpy()); cls.append(r.boxes.cls.cpu().numpy())
        b = torch.tensor(np.concatenate(boxes)); s = torch.tensor(np.concatenate(scores)); c = torch.tensor(np.concatenate(cls))
        keep = torchvision.ops.batched_nms(b, s, c, 0.5) if len(b) else torch.tensor([], dtype=torch.long)
        dets = []
        for i in keep.tolist():
            x0, y0_, x1, y1_ = b[i].int().tolist(); name = names[int(c[i])]
            dets.append({"cls": name, "conf": round(float(s[i]), 3), "box": [x0, y0_, x1, y1_]})
            if name in ("text", "junction", "crossover"):
                continue
            cv2.rectangle(img, (x0, y0_), (x1, y1_), (0, 0, 255), 2)
            cv2.putText(img, f"{name} {s[i]:.2f}", (x0, max(10, y0_ - 4)), 0, 0.5, (200, 0, 0), 1)
        summary[p.stem] = dets
        cv2.imwrite(str(a.out / f"{p.stem}.jpg"), img)
    (a.out / "detections.json").write_text(json.dumps(summary))


if __name__ == "__main__":
    main()
