# Circuit detector: model card

`assets/models/circuit_detector.ablm`, the model behind "Recognize circuit".

| | |
|---|---|
| sha256 | `5632636d752074868c04ec148a1ab3e3e3d51b47b4502f77fe003eaf6356c827` |
| Size | 5,197,916 bytes |
| Architecture | YOLO11n, fused, 22 classes, input 1024 px page width, grayscale |
| Weights | float16, exported as a flat op list by `export_detector.py` |
| Licence | AGPL-3.0, with CC BY 4.0 attribution to CGHD |

## Origin

Fine-tuned in three stages from Ultralytics' `yolo11n` weights (AGPL-3.0),
which is why the model is AGPL-3.0. The last stage ran 15 epochs at lr0 0.002,
`imgsz` 1024.

## Training data

10,563 training images, counting the copies made to oversample rare classes:

| Source | Images | Share | Terms |
|---|---|---|---|
| CGHD photos of hand-drawn circuits | 5,703 | 54% | CC BY 4.0, DFKI, [zenodo.org/records/15333233](https://zenodo.org/records/15333233) |
| Current sources synthesised from CGHD's rings (`build_v2.py`) | 897 | 8% | derived from CGHD, CC BY 4.0 |
| Pages of handwritten electronics notes, tiled | 3,963 | 38% | used with their authors' permission, not redistributed |

Digitize-HCD was used for benchmarks only, never for training. No
non-commercial data went into this model.

## Results

mAP50 on pages held out of training, written by hands also present in the
training set: 0.86 and 0.87 on two sets of notes, 0.82 on a third set. Those test labels started as
detector proposals reviewed by hand, so read the numbers as optimistic. Weakest
classes there: `vss` (recall 0.20-0.42) and `arrow`, which is why the rewrite
also looks for supply arrows in the ink. Class-wise score floors in
`detector.dart`.

## Limits

It reads circuits drawn the way electronics courses draw them: American-style
symbols first, IEC rectangles as resistors. No class for controlled sources
(the rewrite tells a diamond from a ring by its sides). Parts it doesn't know
stay as drawn. See `README.md` for what the rewrite does with each class.
