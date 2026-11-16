# Import

Foreign formats become ordinary notebooks. Markdown sources (Obsidian, Notion)
go through the A4 paginator; OneNote and Samsung Notes keep their own layout
and share `ImportService.importOneNote` (infinite pages for OneNote, fixed
pages when the parsed note carries a page size).

## Samsung Notes (.sdocx)

Pure Dart (`samsung_notes_importer.dart`), so it runs on every platform.
Users get the file from Samsung Notes with *Save as file → Samsung Notes file*.
The format is undocumented; the layout below was read from real files and
cross-checked with the MIT-licensed notes in `bxff/samsung-notes-format`.
No code was taken from either public reverse-engineering project.

- ZIP with `<uuid>.page` per page, `pageIdInfo.dat` (page order),
  `note.note` (title and typed body), `media/mediaInfo.dat` (bind id → file).
- Everything is little-endian. Records are *frames*: u32 size, u16 kind,
  u32 header size, property and field masks (u8 count + bytes), fixed bytes
  up to the header size, then flexible fields in ascending field-bit order.
- Page: layer offset, masks, width/height in px (1080 × 1527, A4 ratio).
  Layers hold object trees: u8 type, u16 children, u32 size (incl. a 32-byte
  trailer). Type 1 = stroke; unknown types are skipped by size.
- Stroke: base frame (kind 0, visible = property bit 3) then frame kind 1.
  Compressed points: f64 x0, y0, then u16 deltas in 1/32 px with a sign bit;
  pressure f32 + u16 deltas / 4096. Style in the flexible part: bit 2 ARGB
  colour, bit 3 pen size in px.
- Pages are drawn one under the other with a 24 px gap (`note.note`), and a
  stroke keeps the coordinates of the page it started on even when it runs
  past the bottom; the importer cuts it there and continues it on the next
  page.
- Typed text lives in `note.note` as one flow over all pages. Pictures are
  object spans at a U+FFFC position; their media id sits in the image fill of
  the shape frame (kind 7, field bit 5). Text sizes are in dp: the importer
  assumes 420 dpi and 1.3 line spacing, so text and picture positions are
  approximate, unlike the ink, which is exact.
- Not imported yet: shapes, tables, voice, PDF backgrounds, pen kinds
  (every stroke becomes a pen, translucent ones a highlighter).
