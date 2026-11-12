"""Turns raw ink into the fixed-width point sequence the encoder consumes.

Three steps, in order:

1. **Scale normalization.** Every ink is mapped so its bounding-box *height*
   is 1 and its centre sits at the origin. Height rather than width, because
   height is what carries meaning in maths: the size ratio between a base and
   its exponent, or between a fraction bar and its numerator, is what tells
   `x^2` from `x2`. Width is just "how long is the expression" and must not
   change the scale, or a long formula would shrink its own symbols to noise.

2. **Arc-length resampling.** Points are re-emitted every `step` units of
   travel along each stroke. Raw sampling density depends on writing speed and
   on the digitizer's rate, so a slowly drawn stroke arrives with three times
   the points of a fast one that has the same shape. Resampling removes that
   and makes the sequence length a function of *how much ink there is*.
   Timestamps are dropped here: after resampling they no longer describe the
   emitted points, and writing speed carries little signal about which symbol
   was written.

3. **Feature assembly**, 6 channels per point:
     x, y        absolute position after normalization — the structural signal
                 (what is raised, what sits under the bar)
     dx, dy      offset from the previous point of the same stroke, 0 at a
                 stroke start — the shape signal, translation invariant
     is_start    1 on the first point of a stroke (pen just went down)
     is_end      1 on the last point of a stroke (pen is about to lift)

Coordinates stay in the digitizer's frame, i.e. y grows *downward*. Only
internal consistency matters, and keeping the raw convention means the Dart
side can feed AbelNotes' StrokePoints in without a flip.
"""

from __future__ import annotations

import numpy as np

#: x, y, dx, dy, is_start, is_end
N_FEATURES = 6


def normalize_strokes(strokes: list[np.ndarray]) -> list[np.ndarray]:
    """Centres the ink on the origin and scales its bounding-box height to 1.

    Returns (n, 2) arrays: the time column is not needed past this point.
    Degenerate inks (a single dot, a perfectly horizontal dash) have a height
    of ~0, which would blow the scale up to infinity; the divisor is therefore
    floored against a fraction of the width and against an absolute epsilon.
    """
    points = [s[:, :2] for s in strokes if len(s) > 0]
    if not points:
        return []

    allp = np.concatenate(points, axis=0)
    lo, hi = allp.min(axis=0), allp.max(axis=0)
    width, height = hi - lo
    scale = 1.0 / max(height, width * 0.05, 1e-6)
    centre = (lo + hi) / 2.0
    return [(p - centre) * scale for p in points]


def resample_stroke(stroke: np.ndarray, step: float) -> np.ndarray:
    """Re-emits `stroke` with points spaced `step` apart along its arc length.

    Always keeps the first and last point, so a stroke shorter than one step
    survives as its two endpoints (or as a single point if it is a dot).
    """
    if len(stroke) == 0:
        return stroke
    # Drop repeated coordinates: they contribute zero-length segments, which
    # would put a 0/0 into the interpolation below.
    keep = np.ones(len(stroke), dtype=bool)
    keep[1:] = np.any(np.diff(stroke, axis=0) != 0, axis=1)
    stroke = stroke[keep]
    if len(stroke) < 2:
        return stroke

    seg = np.linalg.norm(np.diff(stroke, axis=0), axis=1)
    arc = np.concatenate([[0.0], np.cumsum(seg)])
    total = arc[-1]
    n_out = max(int(np.floor(total / step)) + 1, 2)
    targets = np.linspace(0.0, total, n_out)

    out = np.empty((n_out, 2), dtype=np.float32)
    out[:, 0] = np.interp(targets, arc, stroke[:, 0])
    out[:, 1] = np.interp(targets, arc, stroke[:, 1])
    return out


def extract(strokes: list[np.ndarray], step: float = 0.05, max_len: int | None = None) -> np.ndarray:
    """Full pipeline: raw traces -> float32 (L, 6) feature sequence.

    `max_len` truncates from the end when given. Truncation loses the tail of
    the expression, so it should be set high enough that it almost never fires;
    use `stats.py` to check the length distribution before choosing it.
    """
    normalized = normalize_strokes(strokes)
    rows = []
    for stroke in normalized:
        pts = resample_stroke(stroke.astype(np.float32), step)
        if len(pts) == 0:
            continue
        block = np.zeros((len(pts), N_FEATURES), dtype=np.float32)
        block[:, 0:2] = pts
        block[1:, 2:4] = np.diff(pts, axis=0)
        block[0, 4] = 1.0
        block[-1, 5] = 1.0
        rows.append(block)

    if not rows:
        return np.zeros((0, N_FEATURES), dtype=np.float32)
    out = np.concatenate(rows, axis=0)
    return out[:max_len] if max_len else out
