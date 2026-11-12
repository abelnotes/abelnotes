"""The ABLM container the Dart runtime loads (ink_recognizer/model_file.dart).

    magic     4 bytes   "ABLM"
    version   uint32    FORMAT_VERSION
    jsonLen   uint32    length of the header that follows
    json      bytes     {"kind": "...", ..., "tensors": [...]}
    payload   bytes     every tensor, concatenated

Each entry in "tensors" carries name, dtype, shape, byte offset and byte length.
Offsets are 16-byte aligned because Dart's typed-data views refuse a byte offset
that is not a multiple of the element size, and the largest element the runtime
uses is Float32x4 at 16 bytes. Weights are stored as float16 and widened on load;
only storage is narrowed, inference stays in float32.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np

MAGIC = b"ABLM"
FORMAT_VERSION = 1
ALIGN = 16


class Container:
    """Accumulates named tensors, then writes the aligned binary."""

    def __init__(self, header: dict):
        self.header = dict(header)
        self.entries: list[dict] = []
        self.blobs: list[bytes] = []
        self.offset = 0

    def add(self, name: str, array: np.ndarray, dtype: str) -> None:
        np_dtype = {"f16": np.float16, "f32": np.float32, "i32": np.int32}[dtype]
        data = np.ascontiguousarray(array, dtype=np_dtype).tobytes()
        pad = (-self.offset) % ALIGN
        if pad:
            self.blobs.append(b"\0" * pad)
            self.offset += pad
        self.entries.append({
            "name": name,
            "dtype": dtype,
            "shape": list(array.shape),
            "offset": self.offset,
            "bytes": len(data),
        })
        self.blobs.append(data)
        self.offset += len(data)

    def write(self, path: Path) -> int:
        header = dict(self.header, tensors=self.entries)
        blob = json.dumps(header, separators=(",", ":")).encode()
        # Pad the header with spaces (JSON ignores trailing whitespace) so the
        # payload itself starts on an ALIGN boundary. Without this the per-tensor
        # offsets are aligned only relative to the payload, and since the header
        # is variable-length the absolute offsets land anywhere — which is where a
        # typed-data view in Dart refuses to be created.
        blob += b" " * ((-(12 + len(blob))) % ALIGN)
        with open(path, "wb") as f:
            f.write(MAGIC)
            f.write(struct.pack("<II", FORMAT_VERSION, len(blob)))
            f.write(blob)
            for chunk in self.blobs:
                f.write(chunk)
        return path.stat().st_size
