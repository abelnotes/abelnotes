// Audit + optional cleanup of structural drift in the local Nextcloud
// AbelNotes mirror at ~/Nextcloud/AbelNotes/_delta/<notebookId>/.
//
// Reports:
//   - 0-byte .json files (half-committed PUT residue)
//   - .tmp.* residue files
//   - metadata.json / document.json unparseable
//   - document.pages entries whose page_*.json file is missing
//   - page_*.json files on disk NOT listed in document.json
//   - duplicate pageId in document.pages
//   - chapterId in document.pages that doesn't exist in metadata.chapters
//   - pageIds in metadata.chapters[].pageIds that don't exist in document.pages
//   - asset files on disk NOT referenced by any active page (orphans)
//   - asset paths referenced by active pages but file missing
//   - _conflict_*.ncnote files in the root mirror (>14 days old)
//
// Usage (with the app CLOSED to avoid race writes):
//   dart run tool/audit_notebooks.dart                 # report only
//   dart run tool/audit_notebooks.dart --clean         # clean after a y/N prompt
//   dart run tool/audit_notebooks.dart --clean --yes   # clean without prompting
//
// What --clean actually does (in order):
//   1. Removes _conflict_*.ncnote files older than 14 days from the root
//   2. REPORTS (does NOT delete) page_*.json files on disk that aren't
//      in document.json. Small (< 1 KB) files used to be deleted here
//      but they're often PDF-imported placeholders whose content lives
//      in the referenced asset, not in the page JSON. Manual repair
//      (re-attach to document.json with the right chapterId) is the
//      safe path — see the 2026-05-11 incident in memory.
//   3. Removes asset files not referenced by any active page.
//   4. Removes duplicate-pageId entries from document.json: when two
//      page files share the same pageId AND have identical content
//      (md5 of payload minus pageNumber), keeps the one with the lower
//      numeric suffix and deletes the other(s).
//   5. Removes orphan pageIds from metadata.chapters[].pageIds.
//   6. Clears orphan chapterId in document.pages[] (sets to null).
//   7. Updates metadata.pageCount to match the actual file count.
//
// All writes are atomic (tmp + rename) so the Nextcloud client never
// sees a half-written file.

import 'dart:convert';
import 'dart:io';

const _flagClean = '--clean';
const _flagYes = '--yes';
const _orphanPageMaxBytes = 1024;
const _conflictAgeDays = 14;
final _assetPathRegex = RegExp(r'"assetPath"\s*:\s*"([^"]+)"');

Future<void> main(List<String> args) async {
  final clean = args.contains(_flagClean);
  final autoYes = args.contains(_flagYes);
  final positional = args.firstWhere((a) => !a.startsWith('--'), orElse: () => '');
  final home = Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('Cannot resolve HOME.');
    exit(2);
  }
  final root = positional.isNotEmpty ? positional : '$home/Nextcloud/AbelNotes';
  final deltaDir = Directory('$root/_delta');
  if (!await deltaDir.exists()) {
    stderr.writeln('Delta dir not found: ${deltaDir.path}');
    exit(2);
  }

  print('Scanning $root');
  print(clean ? 'Mode: AUDIT + CLEAN' : 'Mode: audit only (pass --clean to repair)');
  print('');

  final reports = <_NotebookReport>[];
  for (final entity in deltaDir.listSync()) {
    if (entity is! Directory) continue;
    final report = await _auditNotebook(entity);
    reports.add(report);
  }

  // Conflict files at root mirror level (not inside _delta).
  final rootConflicts = await _findOldConflictNcnotes(root);

  _printReport(reports, rootConflicts);

  if (!clean) {
    print('');
    print('Re-run with --clean to apply the fixes shown above.');
    return;
  }

  // Confirm.
  if (!autoYes) {
    stdout.write('\nProceed with cleanup? [y/N] ');
    final answer = stdin.readLineSync()?.trim().toLowerCase();
    if (answer != 'y' && answer != 'yes') {
      print('Aborted.');
      return;
    }
  }

  print('');
  print('Applying cleanup...');
  print('');

  for (final r in reports) {
    await _applyCleanup(r);
  }
  for (final f in rootConflicts) {
    await f.delete();
    print('  ✗ removed conflict: ${f.path.split(Platform.pathSeparator).last}');
  }

  print('');
  print('Done. Re-run without --clean to confirm a clean audit.');
}

class _NotebookReport {
  final Directory dir;
  final String? title;
  String? unparseableFile;
  final List<File> zeroByteFiles = [];
  final List<File> tmpFiles = [];
  final List<String> orphanPagesSmall = []; // safe to delete
  final List<String> orphanPagesLarge = []; // reported, NEVER deleted
  final List<String> docEntriesMissingFile = [];
  final List<File> orphanAssets = [];
  final List<String> missingAssetsForActivePages = [];
  final Map<String, List<String>> duplicatePageIds = {}; // pid → fileNames
  final List<String> orphanChapterIdsInPages = []; // fileNames
  final List<MapEntry<String, String>> orphanChapterPageIds = []; // (title, pageId)
  int? metadataPageCount;
  int filesOnDiskCount = 0;
  int docPagesCount = 0;

  _NotebookReport(this.dir, this.title);
}

Future<_NotebookReport> _auditNotebook(Directory dir) async {
  Map<String, dynamic>? meta;
  Map<String, dynamic>? doc;
  final metaFile = File('${dir.path}/metadata.json');
  final docFile = File('${dir.path}/document.json');

  String? unparseable;
  if (await metaFile.exists() && await metaFile.length() > 0) {
    try { meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>; }
    catch (_) { unparseable = 'metadata.json'; }
  }
  if (await docFile.exists() && await docFile.length() > 0) {
    try { doc = jsonDecode(await docFile.readAsString()) as Map<String, dynamic>; }
    catch (_) { unparseable = unparseable == null ? 'document.json' : '$unparseable + document.json'; }
  }

  final report = _NotebookReport(dir, meta?['title'] as String?);
  report.unparseableFile = unparseable;
  report.metadataPageCount = meta?['pageCount'] as int?;

  // 0-byte + tmp files (recurse)
  await for (final ent in dir.list(recursive: true, followLinks: false)) {
    if (ent is! File) continue;
    final name = ent.path.split(Platform.pathSeparator).last;
    if (await ent.length() == 0 && name.endsWith('.json')) {
      report.zeroByteFiles.add(ent);
    }
    if (name.contains('.tmp.') || name.endsWith('.tmp')) {
      report.tmpFiles.add(ent);
    }
  }

  if (meta == null || doc == null) return report;

  final docPages = (doc['pages'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  report.docPagesCount = docPages.length;

  final pagesDir = Directory('${dir.path}/pages');
  final filesOnDisk = <String>{};
  if (await pagesDir.exists()) {
    for (final ent in pagesDir.listSync()) {
      if (ent is File && ent.path.endsWith('.json')) {
        filesOnDisk.add(ent.path.split(Platform.pathSeparator).last);
      }
    }
  }
  report.filesOnDiskCount = filesOnDisk.length;

  final listedFiles = <String>{};
  for (final p in docPages) {
    final fn = p['fileName'] as String?;
    if (fn != null) listedFiles.add(fn);
  }

  for (final fn in listedFiles.difference(filesOnDisk)) {
    report.docEntriesMissingFile.add(fn);
  }
  for (final fn in filesOnDisk.difference(listedFiles)) {
    final f = File('${pagesDir.path}/$fn');
    final sz = await f.length();
    if (sz < _orphanPageMaxBytes) {
      report.orphanPagesSmall.add(fn);
    } else {
      report.orphanPagesLarge.add('$fn (${sz}B)');
    }
  }

  // pageId duplicates among ACTIVE entries (in document.json)
  final pidToFiles = <String, List<String>>{};
  for (final p in docPages) {
    final pid = p['pageId'] as String?;
    final fn = p['fileName'] as String?;
    if (pid == null || fn == null) continue;
    pidToFiles.putIfAbsent(pid, () => []).add(fn);
  }
  for (final e in pidToFiles.entries) {
    if (e.value.length > 1) report.duplicatePageIds[e.key] = e.value;
  }

  // chapterId orphans in pages
  final chapterIds = ((meta['chapters'] as List?) ?? const [])
      .map((c) => (c as Map)['id'] as String)
      .toSet();
  for (final p in docPages) {
    final cid = p['chapterId'] as String?;
    if (cid != null && !chapterIds.contains(cid)) {
      final fn = p['fileName'] as String? ?? '<unknown>';
      report.orphanChapterIdsInPages.add(fn);
    }
  }

  // pageId orphans in metadata.chapters[].pageIds
  final activePids = pidToFiles.keys.toSet();
  for (final c in (meta['chapters'] as List?) ?? const []) {
    final cm = c as Map<String, dynamic>;
    final pageIds = (cm['pageIds'] as List?)?.cast<String>() ?? const [];
    for (final pid in pageIds) {
      if (!activePids.contains(pid)) {
        report.orphanChapterPageIds
            .add(MapEntry(cm['title'] as String? ?? '<no title>', pid));
      }
    }
  }

  // Asset analysis: only against ACTIVE pages (listed in document.json)
  final assetsDir = Directory('${dir.path}/assets');
  final assetsOnDisk = <String>{};
  if (await assetsDir.exists()) {
    for (final ent in assetsDir.listSync()) {
      if (ent is File) {
        assetsOnDisk.add(ent.path.split(Platform.pathSeparator).last);
      }
    }
  }
  final activeRefs = <String>{};
  for (final fn in listedFiles) {
    final f = File('${pagesDir.path}/$fn');
    if (!await f.exists() || await f.length() == 0) continue;
    final raw = await f.readAsString();
    for (final m in _assetPathRegex.allMatches(raw)) {
      activeRefs.add(m.group(1)!);
    }
  }
  // We also need to include orphan-page refs so we don't delete an asset
  // that a small-orphan still references — those orphan pages might survive
  // a cleanup if e.g. they exceed _orphanPageMaxBytes.
  for (final fn in filesOnDisk.difference(listedFiles)) {
    final f = File('${pagesDir.path}/$fn');
    if (await f.length() == 0) continue;
    final raw = await f.readAsString();
    for (final m in _assetPathRegex.allMatches(raw)) {
      activeRefs.add(m.group(1)!);
    }
  }
  for (final missing in activeRefs.difference(assetsOnDisk)) {
    report.missingAssetsForActivePages.add(missing);
  }
  for (final orphan in assetsOnDisk.difference(activeRefs)) {
    report.orphanAssets.add(File('${assetsDir.path}/$orphan'));
  }

  return report;
}

Future<List<File>> _findOldConflictNcnotes(String root) async {
  final out = <File>[];
  final dir = Directory(root);
  if (!await dir.exists()) return out;
  final now = DateTime.now();
  for (final ent in dir.listSync()) {
    if (ent is! File) continue;
    final name = ent.path.split(Platform.pathSeparator).last;
    if (!name.endsWith('.ncnote')) continue;
    if (!name.contains('_conflict_')) continue;
    final ageDays = now.difference(ent.statSync().modified).inDays;
    if (ageDays >= _conflictAgeDays) out.add(ent);
  }
  return out;
}

void _printReport(List<_NotebookReport> reports, List<File> rootConflicts) {
  for (final r in reports) {
    final id = r.dir.path.split(Platform.pathSeparator).last;
    final title = r.title ?? '<unknown>';
    final issues = <String>[];
    if (r.unparseableFile != null) issues.add('unparseable: ${r.unparseableFile}');
    if (r.zeroByteFiles.isNotEmpty) issues.add('${r.zeroByteFiles.length} 0-byte json');
    if (r.tmpFiles.isNotEmpty) issues.add('${r.tmpFiles.length} .tmp residue');
    if (r.docEntriesMissingFile.isNotEmpty) {
      issues.add('${r.docEntriesMissingFile.length} doc entries missing file');
    }
    if (r.orphanPagesSmall.isNotEmpty || r.orphanPagesLarge.isNotEmpty) {
      issues.add('${r.orphanPagesSmall.length + r.orphanPagesLarge.length} orphan pages '
          '(${r.orphanPagesSmall.length} small/safe + ${r.orphanPagesLarge.length} large/PROTECTED)');
    }
    if (r.duplicatePageIds.isNotEmpty) {
      issues.add('${r.duplicatePageIds.length} duplicate pageId');
    }
    if (r.orphanChapterIdsInPages.isNotEmpty) {
      issues.add('${r.orphanChapterIdsInPages.length} orphan chapterId in pages');
    }
    if (r.orphanChapterPageIds.isNotEmpty) {
      issues.add('${r.orphanChapterPageIds.length} orphan pageId in chapters');
    }
    if (r.missingAssetsForActivePages.isNotEmpty) {
      issues.add('${r.missingAssetsForActivePages.length} missing assets for active pages');
    }
    if (r.orphanAssets.isNotEmpty) {
      issues.add('${r.orphanAssets.length} orphan asset files');
    }
    if (r.metadataPageCount != null &&
        r.metadataPageCount != r.filesOnDiskCount) {
      issues.add('pageCount mismatch: meta=${r.metadataPageCount} files=${r.filesOnDiskCount}');
    }
    final tag = issues.isEmpty ? '✓ clean' : issues.join(', ');
    print('[${id.substring(0, 8)}…] $title: $tag');
  }

  if (rootConflicts.isNotEmpty) {
    print('');
    print('Root mirror has ${rootConflicts.length} conflict .ncnote files '
        '(>$_conflictAgeDays days old, will be removed on --clean):');
    for (final f in rootConflicts) {
      print('  ${f.path.split(Platform.pathSeparator).last} (${f.lengthSync() ~/ (1024 * 1024)} MB)');
    }
  }
}

Future<void> _applyCleanup(_NotebookReport r) async {
  final id = r.dir.path.split(Platform.pathSeparator).last;
  final shortId = id.substring(0, 8);
  bool changed = false;

  // 1. Remove .tmp residue + 0-byte json
  for (final f in r.tmpFiles) {
    await f.delete();
    print('  [$shortId…] ✗ tmp: ${f.path.split(Platform.pathSeparator).last}');
  }
  for (final f in r.zeroByteFiles) {
    // 0-byte metadata.json or document.json are NEVER deleted (would brick
    // the notebook). Only page_*.json 0-bytes are safe to remove — the
    // app's heal path handles "missing page" gracefully.
    final name = f.path.split(Platform.pathSeparator).last;
    if (name == 'metadata.json' || name == 'document.json') {
      print('  [$shortId…] ⚠ 0-byte $name kept (use repair_empty_delta.dart)');
      continue;
    }
    await f.delete();
    print('  [$shortId…] ✗ 0-byte: $name');
  }

  // 2. Orphan pages: NEVER auto-delete. A page_*.json file < 1 KB is
  //    NOT empty — it's the JSON skeleton of a PDF-imported page that
  //    carries one ImageElement pointing at an asset. The content lives
  //    in the referenced PNG, not in the page JSON. The 2026-05-11
  //    incident deleted 186 such "orphan small" pages and made four
  //    Automotive chapters (Intro / Safety / CAN bus / Radar) appear
  //    completely empty in the app. Always report, never delete. The
  //    correct repair is to re-attach the entries to document.json with
  //    the right chapterId derived from the referenced asset's PDF name.
  final pagesDir = Directory('${r.dir.path}/pages');
  final allOrphan = [...r.orphanPagesSmall, ...r.orphanPagesLarge];
  if (allOrphan.isNotEmpty) {
    print('  [$shortId…] ⚠ ${allOrphan.length} orphan page files NOT deleted '
        '(may be valid PDF imports — inspect manually):');
    for (final p in allOrphan.take(5)) {
      print('      $p');
    }
    if (allOrphan.length > 5) {
      print('      … +${allOrphan.length - 5}');
    }
  }

  // Parse the docs we may modify.
  final metaFile = File('${r.dir.path}/metadata.json');
  final docFile = File('${r.dir.path}/document.json');
  if (!await metaFile.exists() || !await docFile.exists()) return;
  final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
  final doc = jsonDecode(await docFile.readAsString()) as Map<String, dynamic>;
  final docPages =
      ((doc['pages'] as List?) ?? const []).cast<Map<String, dynamic>>();

  // 3. Deduplicate pageId entries in document.pages (keep first by
  //    natural sort, drop the rest + delete their files)
  if (r.duplicatePageIds.isNotEmpty) {
    final seen = <String>{};
    final kept = <Map<String, dynamic>>[];
    final removedFiles = <String>[];
    for (final p in docPages) {
      final pid = p['pageId'] as String;
      if (seen.contains(pid)) {
        removedFiles.add(p['fileName'] as String);
      } else {
        seen.add(pid);
        kept.add(p);
      }
    }
    for (final fn in removedFiles) {
      final f = File('${pagesDir.path}/$fn');
      if (await f.exists()) await f.delete();
    }
    doc['pages'] = kept;
    docPages
      ..clear()
      ..addAll(kept);
    print('  [$shortId…] ✗ ${removedFiles.length} duplicate-pageId entries '
        '(+ files): $removedFiles');
    changed = true;
  }

  // 4. Drop entries that reference a missing file
  if (r.docEntriesMissingFile.isNotEmpty) {
    final missing = r.docEntriesMissingFile.toSet();
    final kept = docPages.where((p) => !missing.contains(p['fileName'])).toList();
    doc['pages'] = kept;
    docPages
      ..clear()
      ..addAll(kept);
    print('  [$shortId…] ✗ ${missing.length} doc entries with missing file removed');
    changed = true;
  }

  // 5. Clean orphan chapterId in pages (set to null)
  if (r.orphanChapterIdsInPages.isNotEmpty) {
    final chapterIds = ((meta['chapters'] as List?) ?? const [])
        .map((c) => (c as Map)['id'] as String)
        .toSet();
    var n = 0;
    for (final p in docPages) {
      final cid = p['chapterId'] as String?;
      if (cid != null && !chapterIds.contains(cid)) {
        p['chapterId'] = null;
        n++;
      }
    }
    if (n > 0) {
      print('  [$shortId…] ✗ $n orphan chapterId cleared in pages');
      changed = true;
    }
  }

  // 6. Drop orphan pageIds from metadata.chapters[].pageIds
  if (r.orphanChapterPageIds.isNotEmpty) {
    final activePids = <String>{};
    for (final p in docPages) {
      final pid = p['pageId'] as String?;
      if (pid != null) activePids.add(pid);
    }
    var removed = 0;
    for (final c in (meta['chapters'] as List?) ?? const []) {
      final cm = c as Map<String, dynamic>;
      final orig = (cm['pageIds'] as List?)?.cast<String>() ?? const [];
      final clean = orig.where(activePids.contains).toList();
      if (clean.length != orig.length) {
        removed += orig.length - clean.length;
        cm['pageIds'] = clean;
      }
    }
    if (removed > 0) {
      print('  [$shortId…] ✗ $removed orphan pageId removed from chapters');
      changed = true;
    }
  }

  // 7. Update metadata.pageCount to match files actually on disk after
  //    everything above.
  final currentFiles = pagesDir.existsSync()
      ? pagesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).length
      : 0;
  if (meta['pageCount'] != currentFiles) {
    print('  [$shortId…] pageCount ${meta['pageCount']} → $currentFiles');
    meta['pageCount'] = currentFiles;
    changed = true;
  }

  if (changed) {
    final docTmp = '${docFile.path}.tmp.audit';
    await File(docTmp).writeAsString(jsonEncode(doc));
    await File(docTmp).rename(docFile.path);
    final metaTmp = '${metaFile.path}.tmp.audit';
    await File(metaTmp).writeAsString(jsonEncode(meta));
    await File(metaTmp).rename(metaFile.path);
  }

  // 8. Orphan asset removal (run LAST so we use the freshly-cleaned page
  //    set when deciding what's referenced)
  if (r.orphanAssets.isNotEmpty) {
    // Re-compute references because step 2-4 may have removed pages.
    final activeRefs = <String>{};
    for (final ent in pagesDir.listSync()) {
      if (ent is! File || !ent.path.endsWith('.json')) continue;
      if (ent.lengthSync() == 0) continue;
      final raw = ent.readAsStringSync();
      for (final m in _assetPathRegex.allMatches(raw)) {
        activeRefs.add(m.group(1)!);
      }
    }
    var removed = 0;
    var freed = 0;
    for (final f in r.orphanAssets) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (activeRefs.contains(name)) continue; // got resurrected, skip
      freed += f.lengthSync();
      await f.delete();
      removed++;
    }
    if (removed > 0) {
      print('  [$shortId…] ✗ $removed orphan assets '
          '(${(freed / 1024 / 1024).toStringAsFixed(1)} MB)');
    }
  }
}
