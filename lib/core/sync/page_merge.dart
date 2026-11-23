// Pure 3-way merge and structure-diff helpers used when a pull meets local edits.
import 'dart:ui' show Size;

import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/core/providers/canvas_state.dart' show UndoEntry;

bool _listEqStr(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// True if two documents differ in page ORDER, the SET of pages, or any
/// per-page chapter assignment. Ignores pageNumber (a pure renumber is not
/// a meaningful change). Used to decide whether a merge produced something
/// the server doesn't have yet (→ needs an upload to converge).
bool documentStructurallyDiffers(DocumentStructure a, DocumentStructure b) {
  if (a.pages.length != b.pages.length) return true;
  for (var i = 0; i < a.pages.length; i++) {
    if (a.pages[i].fileName != b.pages[i].fileName) return true;
    if (a.pages[i].chapterId != b.pages[i].chapterId) return true;
  }
  return false;
}

/// True if two metadata objects differ in any user-meaningful field
/// (title/cover/paper/tags/author/description/chapter list). Ignores
/// modifiedAt, pageCount, createdAt — those are derived/bookkeeping.
bool metadataStructurallyDiffers(NotebookMetadata a, NotebookMetadata b) {
  if (a.title != b.title ||
      a.coverStyle != b.coverStyle ||
      a.coverColor != b.coverColor ||
      a.paperType != b.paperType ||
      a.paperColor != b.paperColor ||
      a.author != b.author ||
      a.description != b.description) {
    return true;
  }
  if (!_listEqStr(a.tags, b.tags)) return true;
  if (a.chapters.length != b.chapters.length) return true;
  for (var i = 0; i < a.chapters.length; i++) {
    if (a.chapters[i].id != b.chapters[i].id) return true;
    if (a.chapters[i].title != b.chapters[i].title) return true;
  }
  return false;
}

/// 3-way merge of notebook metadata + document structure on pull.
///
/// `base` is the last-synced common ancestor (what we last knew the server
/// had); `local` is the LIVE local state at apply time (may include edits
/// the user made DURING the pull download window); `remote` is what the
/// server has now. Returns the merged metadata + document.
///
/// Core principle that eliminates the cross-device clobber class: a change
/// made on ONE side to something the OTHER side left untouched is ALWAYS
/// kept. Only when both sides changed the SAME thing do we tie-break —
/// low-stakes structural fields (page order, per-page chapter, chapter
/// order) resolve to LOCAL (the device the user is holding, so their most
/// recent action sticks); scalar metadata tie-breaks by `modifiedAt`.
///
/// `survivingFileNames` is the authoritative set of pages that have data in
/// the merged page map; the returned document lists exactly those, once.
///
/// When `baseDoc`/`baseMeta` are null (first sync, no ancestor) we fall
/// back to remote-wins for ordering/scalars — matching legacy behaviour.
({NotebookMetadata metadata, DocumentStructure document}) merge3Way({
  required NotebookMetadata? baseMeta,
  required NotebookMetadata localMeta,
  required NotebookMetadata remoteMeta,
  required DocumentStructure? baseDoc,
  required DocumentStructure localDoc,
  required DocumentStructure remoteDoc,
  required Set<String> survivingFileNames,
}) {
  final baseByFn = {
    for (final e in (baseDoc?.pages ?? const <PageEntry>[])) e.fileName: e
  };
  final localByFn = {for (final e in localDoc.pages) e.fileName: e};
  final remoteByFn = {for (final e in remoteDoc.pages) e.fileName: e};

  List<String> fnOrder(List<PageEntry> p) => p.map((e) => e.fileName).toList();

  // Did `side` reorder the pages it shares with the baseline? Compares the
  // RELATIVE order of common pages, so pure adds/deletes don't read as a
  // reorder.
  bool reordered(List<PageEntry> side) {
    if (baseDoc == null) return false;
    final baseOrder = fnOrder(baseDoc.pages);
    final sideOrder = fnOrder(side);
    final sideSet = sideOrder.toSet();
    final baseSet = baseOrder.toSet();
    final a = baseOrder.where(sideSet.contains).toList();
    final b = sideOrder.where(baseSet.contains).toList();
    return !_listEqStr(a, b);
  }

  final localReordered = reordered(localDoc.pages);
  final remoteReordered = reordered(remoteDoc.pages);
  final List<String> spine;
  if (localReordered && !remoteReordered) {
    spine = fnOrder(localDoc.pages);
  } else if (remoteReordered && !localReordered) {
    spine = fnOrder(remoteDoc.pages);
  } else if (localReordered && remoteReordered) {
    spine = fnOrder(localDoc.pages); // both moved → device wins
  } else {
    spine = fnOrder(remoteDoc.pages); // neither → canonical/remote
  }

  // Final ordered fileName list: spine first, then any surviving fileName
  // not in the spine (remote order, then local order, then bare orphans).
  final seen = <String>{};
  final orderedFns = <String>[];
  void take(Iterable<String> fns) {
    for (final fn in fns) {
      if (survivingFileNames.contains(fn) && seen.add(fn)) orderedFns.add(fn);
    }
  }

  take(spine);
  take(fnOrder(remoteDoc.pages));
  take(fnOrder(localDoc.pages));
  take(survivingFileNames);

  // Per-page chapterId 3-way.
  String? mergeChapterId(String fn) {
    final b = baseByFn[fn]?.chapterId;
    // A side that no longer lists the page didn't move it to "no
    // chapter": read its absence as unchanged, or a page resurrected
    // from one side lost its chapter.
    final l = localByFn.containsKey(fn) ? localByFn[fn]!.chapterId : b;
    final r = remoteByFn.containsKey(fn) ? remoteByFn[fn]!.chapterId : b;
    if (baseDoc == null) return r ?? l;
    final lChanged = l != b;
    final rChanged = r != b;
    if (lChanged && !rChanged) return l;
    if (rChanged && !lChanged) return r;
    if (lChanged && rChanged) return l; // both → device wins
    return r ?? l;
  }

  final mergedEntries = <PageEntry>[];
  for (var i = 0; i < orderedFns.length; i++) {
    final fn = orderedFns[i];
    final src = remoteByFn[fn] ?? localByFn[fn];
    final chapterId = mergeChapterId(fn);
    if (src != null) {
      mergedEntries.add(
          src.copyWith(pageNumber: i + 1, fileName: fn, chapterId: chapterId));
    } else {
      // Pure orphan (page data exists but no entry on either side). Heal
      // reconciles pageId from the page bytes; fileName is a safe stand-in.
      mergedEntries.add(PageEntry(
        pageId: fn,
        pageNumber: i + 1,
        fileName: fn,
        chapterId: chapterId,
      ));
    }
  }

  final mergedDoc = DocumentStructure(
    notebookId: remoteDoc.notebookId,
    formatVersion: remoteDoc.formatVersion,
    pages: mergedEntries,
  );

  // ── Metadata scalar fields (per-field 3-way) ──
  final lMod = localMeta.modifiedAt;
  final rMod = remoteMeta.modifiedAt;
  T pick<T>(T? base, T local, T remote) {
    if (baseMeta == null) return remote;
    final lChanged = local != base;
    final rChanged = remote != base;
    if (lChanged && !rChanged) return local;
    if (rChanged && !lChanged) return remote;
    if (lChanged && rChanged) return rMod.isAfter(lMod) ? remote : local;
    return remote;
  }

  // ── Chapters merged by id (union of adds, honour deletes, title 3-way) ──
  final baseCh = {
    for (final c in (baseMeta?.chapters ?? const <Chapter>[])) c.id: c
  };
  final localCh = {for (final c in localMeta.chapters) c.id: c};
  final remoteCh = {for (final c in remoteMeta.chapters) c.id: c};

  final survivingChIds = <String>{};
  for (final id in {...localCh.keys, ...remoteCh.keys, ...baseCh.keys}) {
    final b = baseCh[id];
    final l = localCh[id];
    final r = remoteCh[id];
    if (b == null) {
      if (l != null || r != null) survivingChIds.add(id); // new on a side
    } else if (l != null && r != null) {
      survivingChIds.add(id);
    } else if (l != null && r == null) {
      if (l != b) survivingChIds.add(id); // remote deleted, local edited → keep
    } else if (l == null && r != null) {
      if (r != b) survivingChIds.add(id); // local deleted, remote edited → keep
    }
    // else: deleted on both (or unchanged-deleted) → drop
  }

  // Chapter order: same spine logic as pages.
  bool chReordered(List<Chapter> side) {
    if (baseMeta == null) return false;
    final baseOrder = baseMeta.chapters.map((c) => c.id).toList();
    final sideOrder = side.map((c) => c.id).toList();
    final ss = sideOrder.toSet();
    final bs = baseOrder.toSet();
    final a = baseOrder.where(ss.contains).toList();
    final b = sideOrder.where(bs.contains).toList();
    return !_listEqStr(a, b);
  }

  final List<String> chSpine;
  final lChRe = chReordered(localMeta.chapters);
  final rChRe = chReordered(remoteMeta.chapters);
  if (lChRe && !rChRe) {
    chSpine = localMeta.chapters.map((c) => c.id).toList();
  } else if (rChRe && !lChRe) {
    chSpine = remoteMeta.chapters.map((c) => c.id).toList();
  } else if (lChRe && rChRe) {
    chSpine = localMeta.chapters.map((c) => c.id).toList();
  } else {
    chSpine = remoteMeta.chapters.map((c) => c.id).toList();
  }

  Chapter mergeChapterObj(String id) {
    final b = baseCh[id];
    final l = localCh[id];
    final r = remoteCh[id];
    final fallback = (r ?? l ?? b)!;
    final title = pick<String>(
        b?.title, l?.title ?? fallback.title, r?.title ?? fallback.title);
    return Chapter(id: id, title: title, pageIds: const []);
  }

  final chSeen = <String>{};
  final mergedChapters = <Chapter>[];
  void takeCh(Iterable<String> ids) {
    for (final id in ids) {
      if (survivingChIds.contains(id) && chSeen.add(id)) {
        mergedChapters.add(mergeChapterObj(id));
      }
    }
  }

  takeCh(chSpine);
  takeCh(remoteMeta.chapters.map((c) => c.id));
  takeCh(localMeta.chapters.map((c) => c.id));

  // Recompute each chapter's pageIds from the merged document so the backup
  // membership list (used by the orphan-heal path) stays consistent with
  // the authoritative PageEntry.chapterId.
  final pageIdsByChapter = <String, List<String>>{};
  for (final e in mergedDoc.pages) {
    final cid = e.chapterId;
    if (cid != null) (pageIdsByChapter[cid] ??= []).add(e.pageId);
  }
  final finalChapters = mergedChapters
      .map((c) => c.copyWith(pageIds: pageIdsByChapter[c.id] ?? const []))
      .toList();

  final mergedMeta = remoteMeta.copyWith(
    title: pick(baseMeta?.title, localMeta.title, remoteMeta.title),
    coverStyle:
        pick(baseMeta?.coverStyle, localMeta.coverStyle, remoteMeta.coverStyle),
    coverColor:
        pick(baseMeta?.coverColor, localMeta.coverColor, remoteMeta.coverColor),
    paperType:
        pick(baseMeta?.paperType, localMeta.paperType, remoteMeta.paperType),
    paperColor:
        pick(baseMeta?.paperColor, localMeta.paperColor, remoteMeta.paperColor),
    tags: pick(baseMeta?.tags, localMeta.tags, remoteMeta.tags),
    author: pick(baseMeta?.author, localMeta.author, remoteMeta.author),
    description: pick(
        baseMeta?.description, localMeta.description, remoteMeta.description),
    chapters: finalChapters,
    pageCount: mergedDoc.pages.length,
    modifiedAt: rMod.isAfter(lMod) ? rMod : lMod,
  );

  return (metadata: mergedMeta, document: mergedDoc);
}

/// Attempts a 3-way element-level merge of ONE page so that two devices
/// editing DIFFERENT parts of the same page converge automatically instead
/// of being forced into a manual conflict. Elements (strokes/text/images/
/// shapes) carry stable ids, so we diff by id against the [base] (last-
/// synced) version:
///   • added on one side only            → keep it
///   • modified on one side only          → take that side
///   • deleted on one side, untouched other → honour the deletion
///   • identical on both                  → keep
///   • SAME element changed on BOTH sides differently, OR edited on one
///     side and deleted on the other      → real conflict ⇒ return null
///     (caller falls back to the page-level conflict UI; nothing is lost).
/// The render engine paints by zIndex, so unioning the element lists is
/// visually correct regardless of list order.
PageData? mergePageElements({
  required PageData base,
  required PageData local,
  required PageData remote,
}) {
  String idOf(ContentElement e) => e.id;
  int zOf(ContentElement e) => e.zIndex;

  final baseById = {for (final e in base.layers.content) idOf(e): e};
  final localById = {for (final e in local.layers.content) idOf(e): e};
  final remoteById = {for (final e in remote.layers.content) idOf(e): e};

  final merged = <ContentElement>[];
  for (final id in {...baseById.keys, ...localById.keys, ...remoteById.keys}) {
    final b = baseById[id];
    final l = localById[id];
    final r = remoteById[id];
    final inL = l != null, inR = r != null, inB = b != null;
    if (inL && inR) {
      if (l == r) {
        merged.add(l);
      } else if (inB && l == b) {
        merged.add(r); // only remote changed
      } else if (inB && r == b) {
        merged.add(l); // only local changed
      } else {
        return null; // both changed the same element → conflict
      }
    } else if (inL && !inR) {
      if (!inB) {
        merged.add(l); // local-added
      } else if (l == b) {
        // remote deleted it, local untouched → honour deletion (drop)
      } else {
        return null; // remote deleted, local edited → conflict
      }
    } else if (!inL && inR) {
      if (!inB) {
        merged.add(r); // remote-added
      } else if (r == b) {
        // local deleted it, remote untouched → honour deletion (drop)
      } else {
        return null; // local deleted, remote edited → conflict
      }
    }
    // else: absent on both live sides → dropped
  }

  // Background: same one-sided-change rule; both-changed-differently = conflict.
  final bb = base.layers.background;
  final lb = local.layers.background;
  final rb = remote.layers.background;
  final BackgroundLayer bg;
  if (lb == rb) {
    bg = lb;
  } else if (lb == bb) {
    bg = rb;
  } else if (rb == bb) {
    bg = lb;
  } else {
    return null; // both changed background differently → conflict
  }

  // Page size: the same rule, or a resize on one side is lost.
  bool sameSize(PageData a, PageData b) =>
      a.width == b.width && a.height == b.height;
  final PageData sized;
  if (sameSize(local, remote) || sameSize(local, base)) {
    sized = remote;
  } else if (sameSize(remote, base)) {
    sized = local;
  } else {
    return null; // both resized differently → conflict
  }

  merged.sort((a, b) => zOf(a).compareTo(zOf(b)));
  final lMod = local.modifiedAt;
  final rMod = remote.modifiedAt;
  return remote.copyWith(
    width: sized.width,
    height: sized.height,
    layers: RenderingLayers(background: bg, content: merged),
    modifiedAt: (rMod != null && lMod != null && rMod.isAfter(lMod))
        ? rMod
        : (lMod ?? rMod),
  );
}

/// Every element of either side, local winning a same-id clash. Fallback
/// for when no base is known or [mergePageElements] finds a conflict.
PageData unionPageElements({
  required PageData local,
  required PageData remote,
}) {
  String idOf(ContentElement e) => e.id;
  int zOf(ContentElement e) => e.zIndex;
  final byId = {
    for (final e in remote.layers.content) idOf(e): e,
    for (final e in local.layers.content) idOf(e): e,
  };
  final content = byId.values.toList()
    ..sort((a, b) => zOf(a).compareTo(zOf(b)));
  return local.copyWith(layers: local.layers.copyWith(content: content));
}

/// Folds into every undo/redo snapshot of a page what a sync merge changed
/// in it (elements added/removed/replaced by the other device), so undoing
/// a local step never rolls the other device's work back.
List<UndoEntry> rebaseHistoryOnMerge(List<UndoEntry> stack,
    Map<String, PageData> before, Map<String, PageData> after) {
  if (stack.isEmpty) return stack;
  String idOf(ContentElement e) => e.id;
  final deltas = <String,
      ({
    Set<String> removed,
    List<ContentElement> added,
    Map<String, ContentElement> changed,
    BackgroundLayer? background,
    Size? size,
  })>{};
  for (final fn in after.keys) {
    final b = before[fn];
    final a = after[fn];
    if (b == null || a == null || identical(b, a)) continue;
    final bById = {for (final e in b.layers.content) idOf(e): e};
    final aById = {for (final e in a.layers.content) idOf(e): e};
    final removed = bById.keys.where((id) => !aById.containsKey(id)).toSet();
    final added = [
      for (final e in a.layers.content)
        if (!bById.containsKey(idOf(e))) e,
    ];
    final changed = {
      for (final e in aById.entries)
        if (bById[e.key] != null && bById[e.key] != e.value) e.key: e.value,
    };
    final bg =
        b.layers.background != a.layers.background ? a.layers.background : null;
    final size = b.width != a.width || b.height != a.height
        ? Size(a.width, a.height)
        : null;
    if (removed.isEmpty &&
        added.isEmpty &&
        changed.isEmpty &&
        bg == null &&
        size == null) {
      continue;
    }
    deltas[fn] = (
      removed: removed,
      added: added,
      changed: changed,
      background: bg,
      size: size,
    );
  }
  if (deltas.isEmpty) return stack;
  return [
    for (final entry in stack)
      if (deltas[entry.pageFileName] case final d?)
        UndoEntry(entry.pageFileName, () {
          final page = entry.pageData;
          final ids = {for (final e in page.layers.content) idOf(e)};
          final content = <ContentElement>[
            for (final e in page.layers.content)
              if (!d.removed.contains(idOf(e))) d.changed[idOf(e)] ?? e,
            for (final e in d.added)
              if (!ids.contains(idOf(e))) e,
          ];
          return page.copyWith(
              width: d.size?.width ?? page.width,
              height: d.size?.height ?? page.height,
              layers: RenderingLayers(
                  background: d.background ?? page.layers.background,
                  content: content));
        }())
      else
        entry,
  ];
}

/// Inserts [extras] into [base] after the nearest page that precedes them
/// in [localOrder] and is already in the result (at the start if none).
List<PageEntry> placeByLocalOrder(
    List<PageEntry> base, List<PageEntry> extras, List<PageEntry> localOrder) {
  final out = [...base];
  final localIndex = {
    for (var i = 0; i < localOrder.length; i++) localOrder[i].fileName: i,
  };
  final sorted = [...extras]..sort((a, b) => (localIndex[a.fileName] ?? 1 << 30)
      .compareTo(localIndex[b.fileName] ?? 1 << 30));
  for (final e in sorted) {
    final li = localIndex[e.fileName];
    var at = out.length;
    if (li != null) {
      at = 0;
      for (var j = li - 1; j >= 0; j--) {
        final k = out.indexWhere((p) => p.fileName == localOrder[j].fileName);
        if (k >= 0) {
          at = k + 1;
          break;
        }
      }
    }
    out.insert(at, e);
  }
  return out;
}
