# Architecture

## Overview

```
┌─────────────────────────────────────────────┐
│                   UI Layer                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │ Library  │  │  Canvas  │  │ Settings  │ │
│  │  Screen  │  │  Screen  │  │  Screen   │ │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘ │
├───────┴──────────────┴──────────────┴───────┤
│              State Management                │
│              (Riverpod Providers)             │
├──────────────────────────────────────────────┤
│              Business Logic                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │  Sync    │  │  File    │  │  Render   │ │
│  │ Service  │  │ Service  │  │  Engine   │ │
│  └────┬─────┘  └────┬─────┘  └───────────┘ │
├───────┴──────────────┴──────────────────────┤
│              Data Layer                      │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │  WebDAV  │  │  SQLite  │  │   Loose   │ │
│  │  Client  │  │  Cache   │  │   Store   │ │
│  └──────────┘  └──────────┘  └───────────┘ │
├──────────────────────────────────────────────┤
│           Nextcloud/WebDAV Server            │
└──────────────────────────────────────────────┘
```

## Architectural decisions

### 1. Offline-first

Every operation writes locally first (loose store on disk + SQLite for the dirty-page queue), then syncs to the WebDAV server in the background. This gives zero-latency writes and full offline operation. Conflicts are resolved with a real element-level 3-way merge, not last-write-wins — see [Conflict handling](#conflict-handling) below.

### 2. Loose store as source of truth

Local persistence is a plain, unpacked directory tree (the "loose store"), not the `.ncnote` ZIP. Each save writes only the pages/assets that actually changed, instead of rewriting the whole archive. The `.ncnote` ZIP is assembled on demand — for export, and as the legacy monolithic format still read as a fallback when no loose store exists yet. See [NCNOTE_FORMAT_GUIDE.md](NCNOTE_FORMAT_GUIDE.md) for the on-disk layout.

### 3. Single-pass rendering

The canvas is painted by one `CustomPainter` (`CanvasRenderEngine`) per frame, not by separate background/content/UI painters. Static content (background, strokes, shapes, text, math) is rendered into a cached `ui.Picture` keyed on the page data, zoom level and image cache, and replayed as-is on subsequent frames; only dynamic overlays (the stroke currently being drawn, lasso selection, shape previews, the laser pointer trail) are painted live on top every frame. A second, separate painter exists only for the PDF text-selection overlay.

### 4. Immutable data model

All models use `Freezed`. Edits create new instances via `copyWith()`, which gives cheap undo/redo (a stack of states), deterministic debugging (every state is a value, not mutated in place), and safety across the async boundaries sync and rendering both cross.

### 5. Adaptive Catmull-Rom stroke smoothing

Raw pointer samples are smoothed with an adaptive Catmull-Rom spline (segment count scales with zoom level) rather than a fixed subdivision. Stroke width isn't a linear function of pressure: the pen tool maps pressure through a square-root curve for better perceived weight, while the calligraphy tool additionally factors in stroke velocity and the angle between stroke direction and nib orientation.

## Data flow: writing a stroke

```
1. PointerDown/Move event (pressure, tilt)
   ↓
2. StrokeCollector accumulates raw points
   ↓
3. Adaptive Catmull-Rom interpolation + pressure/velocity/angle width modulation
   ↓
4. RenderEngine repaints the content layer (cached Picture invalidated)
   ↓
5. StrokeData added to PageModel (Freezed copyWith)
   ↓
6. Riverpod notifies the UI
   ↓
7. SyncService.markDirty(pageId) → SQLite dirty-page queue
   ↓
8. Background: FileService rewrites only that page's JSON in the loose store
   ↓
9. Background: SyncService.syncDelta() uploads dirty pages/assets, then
   document.json, then metadata.json last as the commit marker
```

## Data flow: opening a notebook

```
1. User taps a notebook in Library
   ↓
2. Check local cache (SQLite metadata + ETag)
   ↓
3a. Cache hit + fresh → open straight from the local loose store
3b. Cache miss/stale → WebDAV GET of the remote delta layout
   ↓
4. Read metadata.json + the current page from the loose store
   (or unzip the legacy .ncnote if no loose store exists yet)
   ↓
5. Deserialize PageModel (Freezed fromJson)
   ↓
6. RenderEngine paints the page
   ↓
7. Adjacent pages are prefetched in the background
```

## Conflict handling

Each `ContentElement` (and the page's `BackgroundLayer`) is compared against the last-synced baseline, independently on each side:

```
1. Element changed on only one side  → that side wins automatically, no conflict
2. Element changed/deleted differently on both sides → real conflict, no auto-merge
3. Every element on a page resolves via rule 1 → page is auto-merged silently
4. Otherwise → the page is queued as a PageConflict
```

For a real conflict, the user gets a dedicated resolution screen: local vs. remote previews of the page side by side, a diff summary (strokes/images/shapes/text changed), and a per-page choice — keep local or accept remote (with bulk actions once there are more than a few conflicting pages). A remote deletion clashing with a local edit is shown as its own case, distinct from a content conflict.

## Performance targets

| Metric | Target | How |
|---|---|---|
| Stroke latency | <16ms | Direct `CustomPainter`, no widget rebuild |
| FPS while writing | 60fps | Cached `Picture` for static content, live overlay only for the active stroke |
| Notebook open | <500ms | Loose store + local cache, lazy page loading |
| Incremental sync | <1s per page | Delta sync of only the dirty pages/assets |
| RAM per notebook | <100MB | Off-screen pages deallocated |
