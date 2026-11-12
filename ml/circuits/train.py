"""Detector training with a hard VRAM cap: the GPU also drives the desktop,
and running it dry froze the whole machine."""
import argparse

import torch
from ultralytics import YOLO

ap = argparse.ArgumentParser()
ap.add_argument("--data", required=True)
ap.add_argument("--init", default="yolo11s.pt")
ap.add_argument("--name", required=True)
ap.add_argument("--project", required=True)
ap.add_argument("--epochs", type=int, default=50)
ap.add_argument("--batch", type=int, default=6)
ap.add_argument("--vram", type=float, default=0.7)
ap.add_argument("--lr0", type=float, default=0.01)
a = ap.parse_args()
torch.cuda.set_per_process_memory_fraction(a.vram)
YOLO(a.init).train(data=a.data, imgsz=1024, epochs=a.epochs, batch=a.batch, workers=4,
                   lr0=a.lr0, fliplr=0.5, flipud=0.5, degrees=5, hsv_h=0, hsv_s=0, hsv_v=0.2,
                   project=a.project, name=a.name, exist_ok=True, plots=True)
