# Full-text search (phase 1)

Searches the words in notes across all notebooks, offline, on every platform.

## Data sources
Per page (`page_text.dart`): typed text boxes, LaTeX (matched on its words: Greek
and function names kept, `\frac`, braces and `^_` dropped, so `\omega` finds
"omega" and "frac" finds nothing), and the PDF text layer of imported PDFs.
Chapter titles are one row each (`#chapter:<id>`). Notebook titles come from the
`notebooks` table at query time. Strokes are not text (phase 3).

The extractor reads the stored page JSON (or the binary form's JSON part)
directly, so strokes are never decoded just to index text.

## Index
Table `page_text` (DB version 5), one row per page: `folded` (lower-cased,
diacritics removed, one line per segment, used to match), `raw` (same lines, for
snippets), `sources` bitmask (1 text, 2 math, 4 pdf, 8 ink reserved, 16 chapter),
`parts` (lines per source, to tell which kind a match is), `stamp` (length and
mtime of the page file), plus `page_index`/`chapter_id` so a hit opens at the
right page even when the notebook is not on this device.

No FTS: FTS5 is not guaranteed in every SQLite build (Android, web wasm). A LIKE
scan over a few KB per page is milliseconds for thousands of pages. `SearchIndex.match`
is the only place that knows; swap the engine there.

## Indexer (`search_indexer.dart`)
- `FileService.writes` emits after each committed write (incremental save, full
  save, explode, metadata patch, delete, trash, restore).
- Events are debounced per notebook (2 s), so a writing session is indexed once,
  after the pause. A job re-stats the notebook's pages, re-extracts those whose
  stamp changed (or were reported changed), refreshes page order, drops rows of
  vanished pages. Evicting a notebook keeps its rows.
- Native: extraction in an isolate, one page at a time. Web: main isolate, one
  page per idle-priority slot.
- Reconcile once per launch (3 s after the library appears): queues every library
  notebook; rows of notebooks no longer in the library are deleted.

## Query (`SearchService.search`)
Fold, split on whitespace, AND of `LIKE '%tok%' ESCAPE '\'`. Order: notebooks whose
title matches, then most recently modified, then page order. A snippet is cut
around the first token (40 chars each side) with the matched spans for bold.

## UI
Library search field, 2+ characters: "In your notes" below the notebook grid.
Tapping a hit stores the page as the notebook's resume position
(`openNotebookAndNavigate(startAt:)`) and opens it through the normal paths.

## Find in notebook (phase 2)
`notebook_find.dart` (logic) and `notebook_find_bar.dart` (bar, controller,
highlight painter). No index: the open notebook's pages are in memory.
- Sources: typed text boxes, LaTeX words, PDF text layer (same as phase 1).
- Match: the folded query as a phrase, any whitespace between its words. When
  the phrase is nowhere, each word on its own (the library matches words in any
  order and its hits open here); a one-letter word then only as a whole word.
- Order: page order, then top to bottom on the page.
- Rects: text from the laid-out paragraph (`getBoxesForRange`), falling back to
  the box when rich spans disagree with `content` or folding changed lengths;
  math as its whole box; PDF from char boxes, one rect per line.
- Folded text is cached per immutable `PageData`, so an edit refolds one page.
  5000 pages: about 5 ms per query.
- Opening: Ctrl/Cmd+F, the top bar (wide), More (compact). A library hit in a
  page's text opens with its query found (`pendingFindProvider`), without
  focusing the field (no on-screen keyboard).
- Keys: Enter / Shift+Enter, Esc closes. While the field has focus the canvas
  ignores keys; a tap outside the bar hands focus back to the canvas.
- Navigation: a match on another chapter switches to it; the view moves only on
  the axis the match is hidden on (vertically to a third from the top, never
  leaving an empty band above or below the sheet) and zooms out only when the
  match is bigger than the view.
- Page strip: pages with matches get a marker swipe on their thumbnail.

## Phase 3 hook
Handwriting: another source bit (8). `_compose` in `page_text.dart` takes
per-source segment lists; a recogniser adds its own list, cached by stroke-group
hash + model version. Table and indexer stay as they are; find in notebook needs
the recognised words with their stroke boxes as one more haystack.
