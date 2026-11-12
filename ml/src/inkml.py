"""InkML reader for the MathWriting-2024 dataset.

A MathWriting sample is one <ink> element holding:
  - annotation "label"           : the LaTeX as originally typed by the writer
  - annotation "normalizedLabel"  : same expression put in a canonical form
    (spaces stripped, \\log -> log, redundant braces removed, ...). Only
    present on human-written samples; synthetic ones carry "label" only.
  - annotation "inkCreationMethod": "human" | "synthetic"
  - one <trace> per pen-down..pen-up, as "x y t,x y t,..." with T in ms.

We keep traces separate: stroke boundaries are a real signal for maths
(a fraction bar is one stroke, "=" is two) and the feature extractor turns
them into pen-up/pen-down flags.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

_INKML_NS = "{http://www.w3.org/2003/InkML}"


@dataclass
class Ink:
    """One handwritten expression."""

    #: Strokes in pen order. Each is float32 (n, 3) of (x, y, t_ms).
    strokes: list[np.ndarray] = field(default_factory=list)
    #: All <annotation> elements, keyed by their type attribute.
    annotations: dict[str, str] = field(default_factory=dict)
    source: Path | None = None

    @property
    def label(self) -> str:
        """Preferred training target: normalized form when the dataset ships one."""
        return self.annotations.get("normalizedLabel") or self.annotations.get("label", "")

    @property
    def is_synthetic(self) -> bool:
        return self.annotations.get("inkCreationMethod") == "synthetic"

    @property
    def n_points(self) -> int:
        return sum(len(s) for s in self.strokes)


def read_inkml(path: str | Path) -> Ink:
    """Parses one .inkml file. Raises ET.ParseError on malformed XML."""
    path = Path(path)
    root = ET.parse(path).getroot()

    ink = Ink(source=path)
    for node in root:
        tag = node.tag.removeprefix(_INKML_NS)
        if tag == "annotation":
            ink.annotations[node.attrib.get("type", "")] = (node.text or "").strip()
        elif tag == "trace":
            ink.strokes.append(_parse_trace(node.text or ""))
    return ink


def _parse_trace(text: str) -> np.ndarray:
    """"x y t,x y t,..." -> float32 (n, 3). Points with the wrong arity are dropped."""
    points = []
    for chunk in text.split(","):
        parts = chunk.split()
        if len(parts) == 3:
            points.append((float(parts[0]), float(parts[1]), float(parts[2])))
    if not points:
        return np.zeros((0, 3), dtype=np.float32)
    return np.asarray(points, dtype=np.float32)


def iter_split(root: str | Path, split: str, limit: int | None = None):
    """Yields Inks from <root>/<split>/*.inkml, skipping files that fail to parse.

    Files are visited in sorted order so a `limit` gives a reproducible subset.
    """
    directory = Path(root) / split
    for i, path in enumerate(sorted(directory.glob("*.inkml"))):
        if limit is not None and i >= limit:
            return
        try:
            yield read_inkml(path)
        except ET.ParseError:
            continue
