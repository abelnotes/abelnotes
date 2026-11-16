# Open beside

A second notebook shown read-only next to the one being edited, to read
notes, slides or an imported PDF while writing. Opened from the editor's
⋯ > More > Open beside.

## Why read-only, in the same window

The editor state (`canvasProvider`) is one per app, and the sync engine's
locks live inside that one process. Two editable notebooks would mean a
second editor state everywhere it is read; two app windows (Android
multi-instance) would mean two processes writing the same database and
files with no shared lock. A read-only pane needs neither: it never writes,
never syncs and never enters the library.

## Pieces

- `EditorWithReference` wraps every editor route. With no side notebook it
  is the editor alone. With one, it splits the screen: side by side when the
  area is wide, stacked when it is tall. The editor always keeps the top-left
  corner, so pointer and overlay coordinates are unchanged, and it gets a
  `MediaQuery` sized to its part, which is all its layout reads. A
  `GlobalKey` keeps the editor's state when the split appears or goes:
  rebuilding it would close the notebook.
- `ReferencePane` loads the notebook once (folder on disk, legacy package, or
  the server for a notebook not on this device, kept in memory only) and
  paints its pages with the editor's `CanvasRenderEngine`, fitted to the pane
  width. Zoom: the header buttons or two fingers. Pictures are decoded when a
  page is shown and at most 24 are kept, so a long imported PDF does not stay
  in memory.
- `referenceNotebookProvider` holds the open notebook's id. It is auto-disposed,
  so leaving the editor closes the side notebook.

## Not yet

Typeset formulas use the editor's math raster cache, which the pane does not
fill: they show as their LaTeX source in a tinted box. The side notebook is not refreshed while it
is open; reopen it to see changes made elsewhere.
