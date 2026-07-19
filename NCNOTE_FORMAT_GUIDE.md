# Notebook Storage Format

## Overview

A notebook's data exists in two forms:

1. **Loose store** — an unpacked directory tree, the source of truth for local storage and for delta sync. This is what the app actually reads and writes during normal use.
2. **`.ncnote` archive** — a renamed ZIP, openable with any ZIP tool for manual inspection. It's assembled on demand from the loose store for export/sharing, and it's also the legacy monolithic format the app still reads as a fallback for notebooks that haven't been migrated to a loose store yet.

The two are structurally identical inside — same `metadata.json`/`document.json`/`pages/*.json` — only the container differs (plain directory vs. ZIP).

## On-disk layout

```
AbelNotes/
├── notebooks/
│   ├── <notebookId>.ncnote        # legacy monolithic file (read as fallback only)
│   └── <notebookId>/              # loose store — normal case
│       ├── metadata.json
│       ├── document.json
│       ├── pages/
│       │   ├── page_001.json
│       │   ├── page_002.json
│       │   └── ...
│       ├── assets/
│       │   └── <assetId>          # images, base PDFs, etc.
│       └── symbols.json           # optional, per-notebook symbol library
├── snapshots/<notebookId>/<timestamp>.ncnote   # rolling backups (last 3 saves)
├── trash/<trashId>.ncnote + <trashId>.meta.json
└── abelnotes.db                   # SQLite: dirty-page queue, ETags, notebook index
```

An incremental save touches only the pages/assets that actually changed — it doesn't rewrite the rest of the notebook.

### Remote (WebDAV) layout

The server mirrors the loose store's shape under a per-notebook sync folder, not the `.ncnote` ZIP:

```
.sync/<notebookId>/
├── metadata.json     # uploaded last — acts as the commit marker
├── document.json
├── pages/*.json
├── assets/*
└── symbols.json
```

Pages and assets upload in parallel; `document.json` then `metadata.json` commit last, so a client never observes a notebook with a metadata pointing at pages that haven't landed yet.

## metadata.json

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Physics notes",
  "formatVersion": 1,
  "createdAt": "2026-03-31T10:00:00Z",
  "modifiedAt": "2026-03-31T15:30:00Z",
  "coverStyle": "default",
  "coverColor": 1432809408,
  "paperType": "grid",
  "paperColor": 4294967295,
  "pageCount": 42,
  "tags": ["university", "physics", "2026"],
  "author": "Jane Doe",
  "description": "Notes for the Physics II course"
}
```

## document.json

```json
{
  "notebookId": "550e8400-e29b-41d4-a716-446655440000",
  "formatVersion": 1,
  "pages": [
    {
      "pageId": "a1b2c3d4-...",
      "pageNumber": 1,
      "fileName": "page_001.json",
      "width": 595.0,
      "height": 842.0,
      "thumbnailFile": "page_001.png",
      "lastModified": "2026-03-31T15:30:00Z"
    }
  ]
}
```

## pages/page_001.json

A page has a `BackgroundLayer` (paper type, PDF page reference for annotated imports) and an ordered list of `ContentElement`s. There are five content element types:

```json
{
  "pageId": "a1b2c3d4-...",
  "pageNumber": 1,
  "width": 595.0,
  "height": 842.0,
  "layers": {
    "background": {
      "type": "grid",
      "color": 4294967295,
      "lineSpacing": 25.0,
      "lineColor": 4292927712,
      "pdfAsset": null,
      "pdfPage": 0
    },
    "content": [
      {
        "type": "stroke",
        "id": "stroke-001",
        "zIndex": 0,
        "data": {
          "points": [
            {"x": 100.0, "y": 200.0, "pressure": 0.3, "tilt": 0.0, "timestamp": 0},
            {"x": 105.2, "y": 198.1, "pressure": 0.45, "tilt": 0.1, "timestamp": 8}
          ],
          "toolType": "pen",
          "color": 4278190080,
          "baseWidth": 2.5,
          "isHighlighter": false,
          "opacity": 1.0,
          "timestamp": "2026-03-31T15:28:00Z"
        }
      },
      {
        "type": "text",
        "id": "text-001",
        "zIndex": 1,
        "data": {
          "x": 50.0, "y": 50.0, "width": 400.0, "height": 30.0,
          "content": "Chapter 3: Thermodynamics",
          "fontFamily": "sans-serif", "fontSize": 22.0, "color": 4281545523,
          "bold": true, "italic": false, "alignment": "left",
          "spans": [
            {"text": "Chapter 3: ", "bold": true, "italic": false,
             "underline": false, "strikethrough": false,
             "color": null, "fontSize": null},
            {"text": "Thermodynamics", "bold": false, "italic": true,
             "underline": false, "strikethrough": false,
             "color": 4294901760, "fontSize": 26.0}
          ]
        }
      },
      {
        "type": "shape",
        "id": "shape-001",
        "zIndex": 2,
        "data": {
          "shapeType": "rectangle",
          "x1": 300.0, "y1": 400.0, "x2": 500.0, "y2": 500.0,
          "strokeColor": 4278190335, "strokeWidth": 2.0,
          "fillColor": null, "rotation": 0.0,
          "vertices": null
        }
      },
      {
        "type": "image",
        "id": "img-001",
        "zIndex": 3,
        "data": {
          "x": 100.0, "y": 550.0, "width": 200.0, "height": 150.0,
          "assetPath": "images/img_abc123.png",
          "rotation": 0.0, "opacity": 1.0,
          "locked": false, "flipHorizontal": false, "comment": null
        }
      },
      {
        "type": "math",
        "id": "math-001",
        "zIndex": 4,
        "data": {
          "x": 60.0, "y": 620.0, "width": 220.0, "height": 40.0,
          "latex": "\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}",
          "displayMode": true,
          "color": 4278190080,
          "fontSize": 20.0
        }
      }
    ]
  },
  "pdfTextLayer": null,
  "assetReferences": ["images/img_abc123.png"],
  "createdAt": "2026-03-31T10:00:00Z",
  "modifiedAt": "2026-03-31T15:30:00Z"
}
```

Only the LaTeX source is ever persisted for a `math` element — the rendered glyphs are rasterized at runtime from `latex`, not stored as pixels.

### pdfTextLayer

Pages created by importing a PDF for annotation carry an optional `pdfTextLayer`, separate from the ordered content elements above — it's an overlay-only index of the PDF's own embedded, selectable text (per-run and per-character boxes), used for text selection/copy and full-text search. It is never rendered as drawable content and has no `zIndex`.

```json
{
  "pdfTextLayer": {
    "runs": [
      {
        "text": "Lorem ipsum dolor sit amet",
        "pageIndex": 0,
        "boundingBox": {"x": 40.0, "y": 80.0, "width": 300.0, "height": 14.0},
        "charBoxes": [{"x": 40.0, "y": 80.0, "width": 6.0, "height": 14.0}]
      }
    ]
  }
}
```

## Design notes

### Coordinates
- Origin (0,0) at the top-left
- Unit: points (1 point = 1/72 inch)
- A4: 595 × 842 points

### Pressure
- Range: 0.0 (no contact) — 1.0 (maximum pressure)
- Defaults to 0.5 for input without pressure sensing (mouse)

### Colors
- ARGB integer (e.g. `0xFF1565C0` = Blue 800)
- Alpha in the most significant byte

### Point timestamps
- Milliseconds relative to the start of the stroke
- Used for stroke replay and velocity-dependent width modulation

### Storage
- The loose store keeps every JSON file uncompressed on disk — it's synced and diffed per file, so there's nothing to gain from compressing individual pages.
- The `.ncnote` export/legacy format uses standard ZIP deflate. Embedded PNG/JPEG assets stay in their native format either way.
