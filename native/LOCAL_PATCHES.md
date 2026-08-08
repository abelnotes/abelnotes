# Local patches to `vendor/onenote.rs`

The parser is vendored at the commit in `vendor/onenote.rs/VENDORED_COMMIT`.
Anything we change on top of that commit is listed here, so a future re-vendor
doesn't silently drop it. Re-apply each entry, or drop it once upstream carries
an equivalent fix.

---

## 1. Absolute Windows paths rejected by `resolve_path`

**File:** `crates/parser/src/fs/native_fs.rs` (`resolve_path`, `#[cfg(windows)]` arm)

**Symptom:** every OneNote import on Windows failed with

```
FormatException: parse_section: I/O failure: path contains unexpected prefix
```

**Cause:** the arm called `TypedPath::with_windows_encoding_checked()` on the
incoming path. That method validates a path for *conversion* between encodings
and rejects any input that already carries a prefix — which every absolute
Windows path does (`C:\…`). Confirmed against `typed-path 0.12.3`:

| input | `derive` | `with_windows_encoding_checked` |
|---|---|---|
| `C:\dir\x.one` | Windows | **Err** "path contains unexpected prefix" |
| `dir\x.one` | Windows | Ok |
| `/home/u/x.one` | Unix | Ok |

So the Windows arm could only ever succeed for relative paths. It was written
but never exercised — the bridge had only ever been built on Linux.

**Fix:** convert only when the input is Unix-encoded; pass an
already-Windows-encoded path straight through.

**Upstream:** worth reporting; not filed yet.

---

## 2. `ChunkTerminatorFND` did not end a fragment's node sequence

**File:** `crates/parser/src/onestore/desktop/file_structure/file_node_list_fragment.rs`

**Symptom:** `Unexpected end of file` on the four largest sections of a test
notebook (99, 104, 121 and 133 MB). The seven smaller ones (≤ 40 MB) parsed
fine. Size is correlated, not causal — see below.

**Cause:** per [MS-ONESTORE] 2.4.2 a fragment's node sequence ends at *any* of
three conditions — fewer than 4 bytes left, the node count from the transaction
log reached, or a `ChunkTerminatorFND`. Only the first two were implemented, so
the loop ran on past the terminator into the padding between it and
`nextFragment`. OneNote does not zero that padding, so leftover bytes decode as
a plausible `FileNode` header. In the 133 MB sample the 6 padding bytes at
`0x59198e` read as node type `0x0EF` declaring 81 bytes of data, well past the
end of the fragment.

Nothing about the file is malformed — the fragment's `nextFragment` reference
and its `0x8BC215C38233BA4B` footer both check out. Big files just have far more
fragments, so the odds of landing on ≥ 4 bytes of non-zero padding approach 1.

**Fix:** break out of the loop after a `ChunkTerminatorFND`. The padding is then
skipped by the existing `padding_length` advance. Covered by two unit tests in
the same file.

**Upstream:** worth reporting; not filed yet.

---

## 3. `PageSize` read as a u8

**File:** `crates/parser/src/one/property/page_size.rs`

**Symptom:** `Malformed OneNote file data: page size is not a u8` on
a 99 MB section (only visible once patch 2 let the file get that far).

**Cause:** `PageSize`'s property ID is `0x14001C8B`; bits 26-30 give property
type `0x5`, i.e. a u32 — the same `0x14…` prefix as `PageWidth` / `PageHeight`,
which are read via `to_u32()`. `PageSize::parse` called `to_u8()`, which only
ever succeeded because the property is usually absent and the `None` arm
returns early.

**Fix:** read the value with `to_u32()`.

**Upstream:** worth reporting; not filed yet.

---

## 4. `.onetoc2`: revision nodes and inherited global ID tables

**Files:** `crates/parser/src/onestore/desktop/file_node/object_revision.rs`,
`.../file_node/global_id_table.rs`, `.../objects/object.rs`,
`.../objects/global_id_table.rs`, `.../objects/id_mapping.rs`,
`.../objects/revision.rs`, `.../objects/revision_manifest_list.rs`,
`.../objects/object_group_list.rs`

**Symptom:** `Malformed OneStore data: Unexpected node (parsing Revision):
ObjectRevisionWithRefCountFNDX(…)` on a `.onetoc2`, and after that
`Failed to resolve: Missing mapping for ID (index: 1)`.

**Cause:** two gaps in the same path.

1. `ObjectRevisionWithRefCountFNDX` / `…2FNDX` declare an object — an oid plus
   that revision's property set — but weren't recognised by `Object::try_parse`,
   so the revision loop fell through to its catch-all error. These nodes carry
   no JCID: like the declaration nodes of the same legacy ref-counted family
   their `jci` is fixed at `0x1` and they always carry a property set, giving
   JCID `0x00020001` (`TocContainer`) — which matches the properties actually
   present in the node (`TocChildren`, `SectionColor`).
2. `GlobalIdTableEntry2FNDX` / `…3FNDX` copy entries from the *dependency*
   revision's global ID table. `Entry2` was parsed into a reference map that was
   never applied, and `Entry3` was an outright `unimplemented` error. The
   dependency revision was not reachable from where the table is built:
   `rid_dependent` was bound as `_parent_id` and discarded.

**Fix:** implement `ObjectDeclarationNode` for both revision nodes and accept
them in `Object::try_parse`; keep each revision's global ID table in
`RevisionManifestList` keyed by revision ID, and thread the dependency
revision's table into `GlobalIdTable::parse` so `Entry2` / `Entry3` can resolve
against it.

**Upstream:** worth reporting; not filed yet.
