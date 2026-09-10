#!/usr/bin/env python3
"""Rewrite DT_RUNPATH/DT_RPATH of ELF shared objects to $ORIGIN.

Flutter links each plugin .so with the absolute path of linux/flutter/ephemeral
as its runpath, and that string ships in the package: it names the build
machine's home directory and points at a directory no user has. The bundle
puts every library side by side in lib/, so $ORIGIN is the correct value.

The string is edited in place inside .dynstr, which is why the replacement may
only ever be shorter — the same constraint chrpath works under. No new build
dependency; patchelf is not installed everywhere.

Usage: strip_build_rpath.py <file-or-dir>...
"""

import sys
import pathlib
import struct

DT_NULL, DT_RPATH, DT_STRTAB, DT_RUNPATH = 0, 15, 5, 29
NEW = b"$ORIGIN"


def patch(path: pathlib.Path) -> str | None:
    data = bytearray(path.read_bytes())
    if data[:4] != b"\x7fELF" or data[4] != 2:  # 64-bit only, which is all we ship
        return None
    little = data[5] == 1
    e = "<" if little else ">"
    u16 = lambda o: struct.unpack_from(e + "H", data, o)[0]
    u32 = lambda o: struct.unpack_from(e + "I", data, o)[0]
    u64 = lambda o: struct.unpack_from(e + "Q", data, o)[0]

    phoff, phentsize, phnum = u64(0x20), u16(0x36), u16(0x38)
    dyn_off = dyn_size = 0
    for i in range(phnum):
        ph = phoff + i * phentsize
        if u32(ph) == 2:  # PT_DYNAMIC
            dyn_off, dyn_size = u64(ph + 0x08), u64(ph + 0x20)
            break
    if not dyn_off:
        return None

    # Collect the string-table address and the runpath's offset into it.
    strtab_addr = runpath_entry = None
    for d in range(dyn_off, dyn_off + dyn_size, 16):
        tag, val = u64(d), u64(d + 8)
        if tag == DT_NULL:
            break
        if tag == DT_STRTAB:
            strtab_addr = val
        elif tag in (DT_RPATH, DT_RUNPATH):
            runpath_entry = val
    if strtab_addr is None or runpath_entry is None:
        return None

    # Translate the string table's virtual address to a file offset.
    strtab_off = None
    for i in range(phnum):
        ph = phoff + i * phentsize
        if u32(ph) != 1:  # PT_LOAD
            continue
        vaddr, off, filesz = u64(ph + 0x10), u64(ph + 0x08), u64(ph + 0x20)
        if vaddr <= strtab_addr < vaddr + filesz:
            strtab_off = off + (strtab_addr - vaddr)
            break
    if strtab_off is None:
        return None

    start = strtab_off + runpath_entry
    end = data.index(b"\0", start)
    old = bytes(data[start:end])
    if old == NEW:
        return None
    if len(NEW) > len(old):
        raise SystemExit(f"{path}: cannot lengthen runpath {old!r} to {NEW!r}")
    data[start:end] = NEW + b"\0" * (len(old) - len(NEW))
    path.write_bytes(data)
    return old.decode(errors="replace")


def main() -> None:
    targets: list[pathlib.Path] = []
    for arg in sys.argv[1:]:
        p = pathlib.Path(arg)
        targets.extend(sorted(p.rglob("*.so*")) if p.is_dir() else [p])
    for t in targets:
        if not t.is_file() or t.is_symlink():
            continue
        was = patch(t)
        if was:
            print(f"  {t.name}: {was} -> {NEW.decode()}")


if __name__ == "__main__":
    main()
