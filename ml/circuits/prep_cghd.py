"""CGHD photos -> binarized ink images + YOLO labels, split by drafter.

Photos are binarized on the max RGB channel (drops blue ruling, keeps dark ink)
so training images look like rasterized app ink: dark strokes on white.
"""
import argparse
import json
import pathlib
import random
import xml.etree.ElementTree as ET
from multiprocessing import Pool

import cv2
import numpy as np

# CGHD name -> spike class. Unlisted names are dropped.
CLASS_MAP = {
    "text": "text", "junction": "junction", "crossover": "crossover",
    "terminal": "terminal", "gnd": "gnd", "vss": "vss",
    "voltage.dc": "voltage.dc", "voltage.ac": "voltage.ac",
    "voltage.battery": "voltage.battery",
    "resistor": "resistor", "resistor.adjustable": "resistor",
    "resistor.photo": "resistor",
    "capacitor.unpolarized": "capacitor", "capacitor.polarized": "capacitor.polarized",
    "capacitor.adjustable": "capacitor",
    "inductor": "inductor", "inductor.ferrite": "inductor",
    "diode": "diode", "diode.zener": "diode", "diode.light_emitting": "diode",
    "transistor.bjt": "transistor.bjt", "transistor.photo": "transistor.bjt",
    "transistor.fet": "transistor.fet",
    "operational_amplifier": "opamp",
    "operational_amplifier.schmitt_trigger": "opamp",
    "switch": "switch", "transformer": "transformer",
    "integrated_circuit": "ic", "integrated_circuit.ne555": "ic",
    "integrated_circuit.voltage_regulator": "ic",
}
CLASSES = sorted(set(CLASS_MAP.values()))
VAL_DRAFTERS = {"drafter_3", "drafter_17"}


def binarize(img, long_side):
    gray = img.max(axis=2)
    h, w = gray.shape
    s = long_side / max(h, w)
    gray = cv2.resize(gray, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA)
    blk = max(15, (min(gray.shape) // 20) | 1)
    bw = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                               cv2.THRESH_BINARY, blk, 15)
    # Drop speckle: components smaller than a few pixels.
    n, lab, stats, _ = cv2.connectedComponentsWithStats(255 - bw, connectivity=8)
    keep = np.zeros(n, bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= 12
    return np.where(keep[lab], 0, 255).astype(np.uint8), s


def one(job):
    xml_path, out_img, out_lbl, long_side = job
    root = ET.parse(xml_path).getroot()
    img_path = xml_path.parent.parent / "images" / root.find("filename").text
    img = cv2.imread(str(img_path), cv2.IMREAD_COLOR | cv2.IMREAD_IGNORE_ORIENTATION)
    if img is None:
        return 0
    bw, s = binarize(img, long_side)
    h, w = bw.shape
    lines = []
    for o in root.iter("object"):
        cls = CLASS_MAP.get(o.find("name").text)
        if cls is None:
            continue
        b = o.find("bndbox")
        x0, y0, x1, y1 = (float(b.find(k).text) * s for k in ("xmin", "ymin", "xmax", "ymax"))
        x0, x1 = max(0, x0), min(w, x1)
        y0, y1 = max(0, y0), min(h, y1)
        if x1 - x0 < 2 or y1 - y0 < 2:
            continue
        lines.append(f"{CLASSES.index(cls)} {(x0 + x1) / 2 / w:.6f} {(y0 + y1) / 2 / h:.6f} "
                     f"{(x1 - x0) / w:.6f} {(y1 - y0) / h:.6f}")
    cv2.imwrite(str(out_img), bw)
    out_lbl.write_text("\n".join(lines) + "\n")
    return 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cghd", type=pathlib.Path, required=True)
    ap.add_argument("--out", type=pathlib.Path, required=True)
    ap.add_argument("--long-side", type=int, default=1280)
    a = ap.parse_args()
    jobs = []
    for xml_path in sorted(a.cghd.glob("drafter_*/annotations/*.xml")):
        split = "val" if xml_path.parts[-3] in VAL_DRAFTERS else "train"
        for sub in ("images", "labels"):
            (a.out / sub / split).mkdir(parents=True, exist_ok=True)
        stem = f"{xml_path.parts[-3]}_{xml_path.stem}"
        jobs.append((xml_path, a.out / "images" / split / f"{stem}.png",
                     a.out / "labels" / split / f"{stem}.txt", a.long_side))
    random.shuffle(jobs)
    with Pool() as p:
        done = sum(p.imap_unordered(one, jobs, chunksize=8))
    (a.out / "data.yaml").write_text(
        f"path: {a.out}\ntrain: images/train\nval: images/val\n"
        f"names: {json.dumps(CLASSES)}\n")
    print(done, "images,", len(CLASSES), "classes:", CLASSES)


if __name__ == "__main__":
    main()
