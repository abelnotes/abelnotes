# Sync: page merge and stroke deltas

## Traffic (measured 2026-11-19)

Tool: `test/sync_traffic_measure_test.dart`
(`ABELNOTES_MEASURE=1 flutter test test/sync_traffic_measure_test.dart`).
It writes 120 strokes on one page through the real save and push path
(`CanvasNotifier.save` → `SyncPush` → `SyncService.syncDelta`) against a
fake store that counts the uploaded bytes.

Strokes follow a local corpus of 1523 real pages: points per stroke p50 17,
p90 54, mean 26; pressure and absolute millisecond timestamps on 95% of
points; about 1.2 KB of compact JSON per stroke. Pages in that corpus: p50
0.7 KB (mostly empty), p90 455 KB, p99 1.2 MB, largest 2.6 MB (1679 strokes).

Writing pace: words of 2-6 strokes, 0.15-0.35 s between strokes of a word,
0.3-0.8 s between words, a 1.5-4 s pause every 5-8 words: about 80 strokes a
minute of steady note taking. The editor autosaves 1.2 s after the last edit,
at most 15 s after the first one, which gives one save every ~13 s here.

| page (after writing) | page file, JSON / binary | up per save | up per stroke | up per hour of writing | edit per stroke, JSON / binary | upload / edit |
|---|---|---|---|---|---|---|
| light, 160 strokes | 196 KB / 58 KB | 128 KB | 7.5 KB | 35 MB | 1.2 KB / 0.4 KB | 6x |
| medium, 520 strokes (corpus p90) | 617 KB / 185 KB | 559 KB | 33 KB | 154 MB | 1.1 KB / 0.3 KB | 29x |
| dense, 2120 strokes | 2.6 MB / 782 KB | 2.6 MB | 153 KB | 721 MB | 1.4 KB / 0.4 KB | 106x |
| PDF page (raster, 45-line text layer), 3 images, 420 strokes | 600 KB / 246 KB | 541 KB | 32 KB | 149 MB | 1.2 KB / 0.4 KB | 27x |

Every save uploads the whole page plus `document.json` (~0.2 KB) and
`metadata.json` (~0.3 KB): the page is over 99% of it. Each other device that
has the notebook open then downloads the same whole page once per save, so
the traffic repeats per device. Images and the PDF raster go up once; the PDF
text layer (25 KB median in the corpus) rides along with every save.

Conclusion: worth doing. On any page with real content a save costs 30 to 100
times the strokes it carries, and a dense page costs ~0.7 GB an hour of
writing, up and again down per device. Turning on the binary page codec alone
(`AppConfig.writeBinaryPages`, read by releases since 0.37.11) would cut that
by 3.4x; stroke deltas cut it to the size of the edit.

### With stroke chunks on (measured 2026-11-19, same tool and pace)

The tool runs every page twice, flags off and on. Upload per save:

| page | flags off | chunks: first save of the session | chunks: later saves | chunks: close |
|---|---|---|---|---|
| light, 160 strokes | 128 KB | 66 KB | 7.8 KB | 196 KB |
| medium, 520 strokes | 559 KB | 495 KB | 7.6 KB | 618 KB |
| dense, 2120 strokes | 2.6 MB | 2.5 MB | 8.4 KB | 2.6 MB |
| PDF page, 420 strokes | 541 KB | 474 KB | 7.7 KB | 601 KB |

A later save is ~17 strokes in ~7 KB of chunk plus ~0.5 KB of
document.json and metadata.json: on the dense page 310 times less than
today, and another device pulling it downloads that chunk, not the page.
What is left is whole-page writes: the first save of a page in a session
(no baseline this service read or wrote yet), the compaction every 24
chunks (~5 minutes of steady writing) and the one on close. An hour of
steady writing on the dense page: ~2.4 MB of chunks plus ~12 compactions
of 2.6 MB, about 34 MB instead of 721 MB (21x). Raising the chunk limit
or seeding the baseline at open (both below) would cut most of the rest.

## Stroke deltas (Track S design)

A save uploads what changed on a page as a small immutable op chunk next to
the page instead of rewriting the page. Two flags: `StrokeOps.read` (list
and apply chunks) and `StrokeOps.write` (write them). With both off nothing
below runs and the sync is byte for byte what it was. Rollout is two
releases: first one that reads (writing stays off), then writing on, once
few devices run a release that does not read. The current release ships
read on, write off: see "Read on, write off" below.

### Files

```
_delta/<notebook>/pages/page_003.json            snapshot, as today
_delta/<notebook>/ops/page_003~k3f9a2x1~lz8q0c.abop   chunk: <page stem>~<device>~<clock>
```

- `ops/` is its own folder: old releases list `pages/` and take every
  `.json` there for a page, so a chunk must never sit in it or end in `.json`.
- device: 8 random base-36 characters, new for each `SyncService`. Only
  needs to be unique; ordering comes from the clock.
- clock: hybrid Lamport, `max(last + 1, now in ms, highest clock seen in a
  listing + 1)`, base 36 in the name. Order of chunks is (clock, device).
- A chunk is written once with an atomic upload and never changed: a name
  identifies its content, so a listing is enough to know what a page holds.

Chunk bytes: `ABOP`, version byte `1`, varint length, UTF-8 JSON header, then
the elements of its add and replace ops as one page in the page codec
(binary form, JSON when a point is not finite), so elements are encoded
exactly like pages. Header:

```
{"pageId": "...",              // chunk applies only to the page with this id
 "ops": [["a","<id>"],["r","<id>"],["d","<id>"]],   // add, replace, delete
 "n": 2,                       // elements in the payload (a + r), checked
 "modifiedAt": "...",          // page modifiedAt after this edit
 "header": {...}}              // only when page fields other than content
                               // and modifiedAt changed (size, background,
                               // text layer): the page JSON without content
```

### Applying

A page = its snapshot, then its live chunks in (clock, device) order, ops in
the order they are listed:

- add: appended if the id is absent, ignored if present (a replay is a no-op).
- replace: swaps the element in place if present, ignored if absent: a
  delete wins over a concurrent move or recolor.
- delete: removes the id if present.
- header and modifiedAt: the later chunk wins.

Live chunks are those listed for the page, minus those whose `pageId` is not
the snapshot's (a file name reused after a delete) and those the snapshot
says it folded (`"foldedOps": [...]`, the first key of a snapshot written by
a compaction; old releases ignore the key). Two devices that drew on one
page offline produce two chunks of adds: both apply, no conflict.

### Versions and pull

The pull and push compare per-page version strings and never parse them.
With `read` on, a page with chunks gets the version
`<snapshot etag>|<device>~<clock>,...` (chunk ids sorted), a page without
chunks keeps the bare etag. So:

- `getRemotePageEtags` lists `pages/` and `ops/` (one more PROPFIND, only on
  the slow path and the safety net, as today) and reports those versions.
  The whole pull (changed pages, conflicts, 3-way merge, ghost and
  half-commit detection) runs unchanged on them.
- `downloadDeltaPage` downloads the snapshot (kept in memory by etag) and
  the chunks of the version it is asked for (immutable, kept by name), and
  applies them. A second device pulling a page after one save downloads one
  small chunk, not the page.
- `getPageVersions` (the push precheck) reports the same versions, so a
  chunk from another device makes the push pull first, as a page write does
  today.
- `downloadExplodedFull` applies chunks too.

### Push

`syncDelta` writes a chunk for a dirty page only when all of these hold,
otherwise it writes the whole page as today:

1. `write` is on and the caller passed the page's sync baseline
   (`lastSyncedPages`), and that object is the one this `SyncService`
   itself last downloaded or uploaded for the page, at the version the
   caller passes as base. A baseline rebuilt after a restart (the emptied
   page of an unpushed notebook) never qualifies: deletes made offline
   would be lost from a diff against it.
2. The diff baseline to page is expressible: applying it to the baseline
   gives back exactly the page's elements and fields. List order is not
   kept (painting sorts by zIndex), so a merge that interleaved the two
   sides still goes as a chunk. Duplicate ids, or another page id, write
   the page.
3. The page has fewer than 24 live chunks, and on a page over 32 KB its
   chunks stay smaller than the snapshot; else this save compacts.

After the chunk upload the snapshot must still exist: a page deleted on
another device meanwhile drops the chunk and raises
`RemotePagesChangedException`, so the pull shows the deletion conflict as
it does today. document.json and metadata.json then go up as today:
metadata stays the commit marker that wakes the other devices.

### Compaction

A whole-page write while chunks are live is a compaction: the snapshot is
the materialized page plus `"foldedOps"` naming the chunks of the base
version, written with If-Match on the snapshot part of that version. On
success the folded chunks are deleted, best effort: a chunk that survives is
skipped by readers because the snapshot names it, and deleted by the next
compaction. Two devices compacting at once: one If-Match fails (412), that
device gets `RemotePagesChangedException`, pulls, merges and pushes again,
as for any page written on two devices today. Its chunks are never deleted
by the loser, and the winner deletes only what it folded, so a chunk written
during a compaction stays live on top of the new snapshot.

### Old releases and mixed fleets

Old releases read snapshots only. While a device writes chunks, an old one
sees its strokes at the next compaction: after 24 chunks on a page, and
when the notebook is closed (`closeNotebook` writes every page whose version
has chunks whole before it lets go). An old release writing a page over a snapshot keeps
the chunks live on top of its write: its adds and deletes stand, chunk adds
stay (union), and a chunk replace of an element it also changed wins over
its change.

### Read on, write off

What a device of the reading release does, next to a writer and alone:

- It lists `ops/` with `pages/` (and in the push precheck) and reads
  pages as snapshot plus chunks, so it pulls and merges a writer's strokes
  like any other change. A missing `ops/` is no chunks: on a folder no
  writer touched, the versions are the bare etags and the page bytes it
  writes are the ones the release before wrote (no `foldedOps` key without
  chunks).
- It never writes a chunk and never creates `ops/`: `_chunkFor` and the
  compaction requests (24 chunks, the size rule, close) need `write`.
- When it saves a page whose base version has chunks, its page write is a
  compaction: the snapshot holds the materialized page, names the chunks
  of its base in `foldedOps`, goes up with If-Match on the snapshot part of
  that base, and the folded chunks are deleted after it landed. This is
  not optional. Without `foldedOps` the chunks stay live on top of its
  write and replay: an element it erased comes back, a stroke it moved
  jumps back (the old-release case above). The race with a writer is the
  one of two compactions: a writer's compaction in between fails the
  If-Match, so the reader pulls, merges and pushes again; a chunk written
  in between is not in its base, so it is not folded or deleted and stays
  live on top of the new snapshot.
- It does not sweep orphan chunks (chunks of a page the `pages/` listing
  lacks). Readers have no use for it, since only writers make chunks, and
  a page replaced by an atomic upload can be briefly missing from a
  listing (a WebDAV MOVE with Overwrite may delete the target first): a sweep
  then would delete live chunks of a page that went without compaction for
  an hour. Writers still sweep; that window is open for the writing release.

Tests: `test/stroke_ops_devices_test.dart` ("read on, write off") and
`test/stroke_ops_sync_test.dart`.

### Deletes, undo, conflicts

- Deleting a page deletes its chunks too (best effort); leftovers never
  apply to a new page with the same file name (pageId check).
- Undo needs nothing: an undone erase is an add of the same id after the
  delete; an undone move is a replace.
- Conflicts and their UI are untouched: they come from the 3-way merge on
  materialized pages, exactly as with page writes.
- Drive: same files through `RemoteStore`; nothing backend-specific.

### Failure cases

| failure | effect |
|---|---|
| crash after the chunk upload, before metadata.json | chunk is live; the next listing shows a new version, other devices pull it at the next safety-net PROPFIND; this device's restart has no baseline, so it writes the page (compaction) after the precheck pulled the chunk in |
| chunk upload cut off | atomic upload: the file is whole or absent |
| damaged chunk | `FormatException` like a damaged page: the pull's corruption path; the next whole-page write folds it |
| chunk deletes after compaction fail | skipped by `foldedOps`, deleted by the next compaction |
| two compactions at once | If-Match: one wins, the other merges and retries |
| page deleted while a chunk goes up | snapshot check after upload: chunk removed, deletion conflict as today |
| old release rewrites a snapshot with folded chunks still listed (crash between compaction and chunk delete) | `foldedOps` lost, those chunks replay: a replace can undo that release's later change to the same element, an add can bring back an element it erased; no ink is lost, and the next compaction ends it |
| clock skew between devices | only orders concurrent replaces of one element; ties broken by device |
| listing of `ops/` fails | the pull fails as for `pages/` (never read as "no chunks" unless 404) |

### Not done yet

- Seed the chunk baseline when a notebook opens from disk (a page not
  marked dirty is what the server held at its stored version), so the first
  save of a session is a chunk too. Needs its own proof that the disk and
  the stored version cannot disagree.
- Tune `maxLiveChunks` (24) against the cost of a compaction on big pages;
  the size rule already compacts small pages early.
- Gate writing on the fleet: metadata.json written by a release without
  chunks loses any extra key, which can tell a writer that such a release is
  active on the notebook, so it can go back to page writes for a while.
- `flushPendingWork` on app pause does not compact; only `closeNotebook`
  does.
- Before `write` goes on: make the orphan sweep need the page missing from
  two listings in a row, so a snapshot mid-replace is never read as a
  deleted page.

## Pull baselines

The meta ETag and the page ETags a device last saw decide what a pull
downloads: an unknown page is fetched. They used to live only in
shared_preferences, which are per install, while the notebooks folder is not:
a native build and the flatpak on one PC both use `~/Documents/AbelNotes`, so
the second one downloaded every page of a notebook the first had synced
(735 pages, ~3.5 min).

`SyncBaselines` (lib/core/services/sync_baselines.dart) keeps them in the
store folder too, `notebooks/<id>/.sync_baseline.json`:

```json
{"v": 1, "backends": {"<key>": {"meta": "…", "pages": {"page_001.json": "…"}, "at": 1732190000000}}}
```

- Key: sha256 (first 32 hex) of what `RemoteStore.baselineIdentity` names:
  WebDAV = DAV URL (scheme and host lowercased, user included) + remote root;
  Drive = id of the root folder, unique per account and folder. A baseline
  read on another server would keep stale pages, so an entry is only ever
  used by the server that wrote it. At most 4 entries, oldest dropped.
- It describes what is on this disk, so it is written where the prefs were,
  after the local write; writes are tmp + rename under a per-file lock.
  Missing, corrupt or another `v`: no baseline, the pull fetches every page
  (as on a fresh install). The store folder is never created for it, so a
  library stub stays a stub.
- Read order: the file's entry, else this install's prefs, which are then
  copied into the file. Prefs are still written: older builds after a
  downgrade read them, and they are the fallback when the key is unknown
  (Drive offline at open, no remote).
- Never leaves the device: `assembleZipFromLooseStore` lists the files it
  packs, snapshots skip it, an archive entry with this name is ignored when a
  package is exploded (no planting through an import), and a rebuild of the
  store (rename, cover, restore) carries it over as prefs did. Search,
  folder sync and library scanning only read named files.
- Forgetting: a disconnect or backend switch drops the entry of the remote
  being left in every notebook (all entries when it can't be named); entries
  of other servers belong to other installs on the same folder. Per-notebook
  forgets (deleted elsewhere, rebuild on the server) drop the current
  server's entry; the settings "re-download" drops the whole file.
- Not moved: pending deletes, the pending metadata commit and the unpushed
  merge base. They are this install's queued work, paired with its own
  retry state, and two installs replaying them is not obviously safe.
- Web: same code over the IndexedDB-backed file layer (`io_web.dart`).
- Windows: `File.rename` replaces an existing target (documented for every
  platform), but fails while another process holds it open (a second
  install, an indexer, a sync client). The write then deletes the target and
  renames again: a crash in between leaves no file, i.e. a full pull.
- The editor's first pull waits for the baseline to load
  (`SyncSession.baselineLoad`); before, a fast server could win that race
  and diff against an empty map.
