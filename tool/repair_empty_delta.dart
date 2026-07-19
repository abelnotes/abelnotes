// ignore_for_file: avoid_dynamic_calls

// Repair 0-byte files in the local Nextcloud AbelNotes mirror.
//
// Symptom: a previous half-committed sync (PUT acknowledged but body
// got dropped at the wire) left some `metadata.json`, `document.json`,
// or `pages/page_XXX.json` files at exactly 0 bytes on the server.
// Nextcloud syncs the 0-byte file to local. The app's pull repeatedly
// fails to decode them → the affected notebook can't be fully loaded.
//
// This script walks ~/Nextcloud/AbelNotes/_delta/<notebookId>/ and:
//   1. By default (no flags): REPORT — list every 0-byte .json file
//      grouped by notebook, suggest the repair / delete commands.
//   2. With --rebuild-document: when document.json is 0 bytes, rebuild
//      it from the CURRENT state of pages/ + metadata.json. Preserves
//      the user's recent work — preferred over restoring from a stale
//      .ncnote backup that would revert the notebook to its older state.
//   3. With --repair: attempt to recover each empty file from the
//      corresponding root .ncnote ZIP (the library cache's safety-net
//      copy). Use only when the .ncnote is reasonably fresh — older
//      backups will lose recent work.
//   4. With --delete-empty: hard-delete every remaining 0-byte file.
//      The app handles missing assets/pages gracefully.
//
// Usage (with the app CLOSED):
//   dart run tool/repair_empty_delta.dart                       # report
//   dart run tool/repair_empty_delta.dart --rebuild-document    # rebuild doc.json
//   dart run tool/repair_empty_delta.dart --repair              # restore from .ncnote
//   dart run tool/repair_empty_delta.dart --delete-empty        # nuke empties
//
// Typical recovery for the "0-byte document.json + 1 lost page" case:
//   dart run tool/repair_empty_delta.dart --rebuild-document --delete-empty

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

const _flagRepair = '--repair';
const _flagDelete = '--delete-empty';
const _flagRebuildDoc = '--rebuild-document';

Future<void> main(List<String> args) async {
  final repair = args.contains(_flagRepair);
  final deleteEmpty = args.contains(_flagDelete);
  final rebuildDoc = args.contains(_flagRebuildDoc);
  final dryRun = !repair && !deleteEmpty && !rebuildDoc;

  final home = Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('Cannot resolve HOME.');
    exit(2);
  }
  // Positional override of root.
  final positional =
      args.firstWhere((a) => !a.startsWith('--'), orElse: () => '');
  final root = positional.isNotEmpty ? positional : '$home/Nextcloud/AbelNotes';
  final deltaDir = Directory('$root/_delta');
  if (!await deltaDir.exists()) {
    stderr.writeln('Delta dir not found: ${deltaDir.path}');
    exit(2);
  }

  print('Scanning ${deltaDir.path} for 0-byte .json files...');
  if (dryRun) {
    print('(dry run — pass --repair and/or --delete-empty to act)');
  }
  print('');

  // Collect by notebook id.
  final byNotebook = <String, List<File>>{};
  await for (final entity in deltaDir.list()) {
    if (entity is! Directory) continue;
    final notebookId = entity.path.split(Platform.pathSeparator).last;
    final empties = <File>[];
    await _collectEmptyJsonFiles(entity, empties);
    if (empties.isNotEmpty) {
      byNotebook[notebookId] = empties;
    }
  }

  if (byNotebook.isEmpty) {
    print('No 0-byte .json files found. Nothing to repair.');
    return;
  }

  var totalRepaired = 0;
  var totalDeleted = 0;
  var totalSkipped = 0;
  var totalReported = 0;

  for (final entry in byNotebook.entries) {
    final notebookId = entry.key;
    final empties = entry.value;
    print('━━━ Notebook $notebookId (${empties.length} empty) ━━━');
    for (final f in empties) {
      final rel = f.path.substring(deltaDir.path.length + 1);
      print('  · $rel');
      totalReported++;
    }

    if (dryRun) continue;

    final notebookDeltaDir = Directory('${deltaDir.path}/$notebookId');

    // ── Repair phase ──
    if (repair) {
      final ncnotePath = await _findRootNcnote(root, notebookId);
      if (ncnotePath == null) {
        print('  ⚠ No root .ncnote found for $notebookId — cannot repair, '
            'consider --delete-empty.');
      } else {
        final repaired = await _repairFromNcnote(
            ncnotePath, notebookDeltaDir, empties);
        totalRepaired += repaired;
        // Drop repaired files from the empties list so --delete-empty
        // below doesn't touch them.
        empties.removeWhere((f) => !File(f.path).existsSync() ||
            File(f.path).lengthSync() > 0);
      }
    }

    // ── Rebuild document.json from server-side state ──
    //
    // Preferred over .ncnote restore when:
    //   - metadata.json is intact (we need it for chapter info)
    //   - the user has done work AFTER the .ncnote backup date and
    //     loses progress if we revert to an old document
    //
    // Builds document.json from a directory walk of the pages folder:
    // for each valid (non-empty) page_XXX.json we decode it for
    // pageId / pageNumber / width / height, then attach the chapterId
    // by looking up pageId in metadata.json's chapters[].pageIds.
    if (rebuildDoc) {
      final docFile = File('${notebookDeltaDir.path}/document.json');
      if (await docFile.exists() && await docFile.length() == 0) {
        final ok = await _rebuildDocumentFromPages(notebookDeltaDir);
        if (ok) {
          totalRepaired++;
          // Drop document.json from the empties list so --delete-empty
          // below doesn't nuke our freshly rebuilt file.
          empties.removeWhere((f) =>
              f.path.endsWith('document.json'));
        }
      }
    }

    // ── Delete phase ──
    if (deleteEmpty) {
      for (final f in empties) {
        if (!await f.exists()) continue;
        if (await f.length() > 0) {
          // Got repaired in the prior pass — skip.
          continue;
        }
        await f.delete();
        final rel = f.path.substring(deltaDir.path.length + 1);
        print('  ✗ removed: $rel');
        totalDeleted++;
      }
    } else if (repair) {
      // Repair-only mode: anything still empty stays as-is.
      for (final f in empties) {
        if (await f.exists() && await f.length() == 0) {
          totalSkipped++;
        }
      }
    }
    print('');
  }

  print('═══ Summary ═══');
  print('  Empty files found: $totalReported');
  if (!dryRun) {
    print('  Repaired from .ncnote: $totalRepaired');
    print('  Deleted: $totalDeleted');
    if (repair && !deleteEmpty) {
      print('  Still empty (no recovery): $totalSkipped');
    }
  } else {
    print('');
    print('Re-run with --repair to attempt restoration from local .ncnote');
    print('Re-run with --delete-empty to remove the empty files so the app');
    print('  can fall back to re-syncing from another device.');
  }
}

Future<void> _collectEmptyJsonFiles(
    Directory dir, List<File> out) async {
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final length = await entity.length();
    if (length == 0) out.add(entity);
  }
}

/// Find the root .ncnote (safety-net copy) for [notebookId]. Returns
/// null if no candidate exists in the Nextcloud root. Conflict-suffix
/// files (`_conflict_<ts>.ncnote`) are skipped.
Future<String?> _findRootNcnote(String root, String notebookId) async {
  final dir = Directory(root);
  if (!await dir.exists()) return null;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.path.split(Platform.pathSeparator).last;
    if (!name.endsWith('.ncnote')) continue;
    if (name.contains('_conflict_')) continue;
    if (name.contains(notebookId)) {
      // Check it's not empty itself.
      if (await entity.length() > 0) return entity.path;
    }
  }
  return null;
}

/// Rebuild a notebook's `document.json` from the current state of its
/// `pages/` folder + intact `metadata.json`. Used when the server's
/// document.json is 0 bytes but the page files are all still valid
/// and contain newer work than any local .ncnote backup. Preserves
/// chapter assignments via metadata.chapters[].pageIds.
Future<bool> _rebuildDocumentFromPages(Directory notebookDeltaDir) async {
  final metadataFile = File('${notebookDeltaDir.path}/metadata.json');
  if (!await metadataFile.exists() || await metadataFile.length() == 0) {
    print('  ⚠ Cannot rebuild — metadata.json is missing or empty');
    return false;
  }
  final pagesDir = Directory('${notebookDeltaDir.path}/pages');
  if (!await pagesDir.exists()) {
    print('  ⚠ Cannot rebuild — pages/ folder missing');
    return false;
  }

  final metaJson = jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
  final notebookId = metaJson['id'] as String;
  final formatVersion = metaJson['formatVersion'] as int? ?? 1;
  final chapters = (metaJson['chapters'] as List?) ?? const [];

  // Build pageId → chapterId index from metadata's chapter assignments.
  final pageIdToChapter = <String, String>{};
  for (final c in chapters) {
    final cm = c as Map<String, dynamic>;
    final cid = cm['id'] as String;
    final pageIds = (cm['pageIds'] as List?) ?? const [];
    for (final p in pageIds) {
      pageIdToChapter[p as String] = cid;
    }
  }

  // Walk pages/, decode each, collect entries.
  final entries = <Map<String, dynamic>>[];
  var skipped = 0;
  await for (final entity in pagesDir.list()) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    if (await entity.length() == 0) {
      skipped++;
      continue;
    }
    try {
      final raw = await entity.readAsString();
      final pageJson = jsonDecode(raw) as Map<String, dynamic>;
      final pageId = pageJson['pageId'] as String;
      final pageNumber = (pageJson['pageNumber'] as num).toInt();
      final width = (pageJson['width'] as num).toDouble();
      final height = (pageJson['height'] as num).toDouble();
      final fileName = entity.path.split(Platform.pathSeparator).last;
      final chapterId = pageIdToChapter[pageId];

      // Field name MUST be `pageId` (matches PageEntry.pageId in
      // ncnote_format.dart). Writing `id` instead made the app's
      // DocumentStructure.fromJson cast null→String and abort the
      // entire pull. The nullable fields (thumbnailFile, chapterId,
      // lastModified) are emitted explicitly as null so the rebuilt
      // file matches the schema produced by the running app exactly.
      entries.add(<String, dynamic>{
        'pageId': pageId,
        'pageNumber': pageNumber,
        'fileName': fileName,
        'width': width,
        'height': height,
        'thumbnailFile': null,
        'chapterId': chapterId,
        'lastModified': null,
      });
    } catch (e) {
      print('  ⚠ Page ${entity.path.split(Platform.pathSeparator).last} '
          'unreadable: $e');
      skipped++;
    }
  }

  // Sort by pageNumber so the document.pages list matches the user's
  // navigation order (the app uses this for next/prev page).
  entries.sort((a, b) =>
      (a['pageNumber'] as int).compareTo(b['pageNumber'] as int));

  final document = <String, dynamic>{
    'notebookId': notebookId,
    'formatVersion': formatVersion,
    'pages': entries,
  };

  final docFile = File('${notebookDeltaDir.path}/document.json');
  final docJson = jsonEncode(document);
  // Atomic rewrite.
  final tmp = '${docFile.path}.tmp.rebuild';
  await File(tmp).writeAsBytes(utf8.encode(docJson));
  await File(tmp).rename(docFile.path);
  print('  ✓ document.json rebuilt: ${entries.length} pages '
      '($skipped skipped, ${docJson.length} bytes)');
  return true;
}

/// Restore [empties] from a root .ncnote ZIP. Returns the count of
/// successfully repaired files. Files not present in the archive (or
/// also empty in the archive) are left untouched.
Future<int> _repairFromNcnote(
    String ncnotePath, Directory deltaDir, List<File> empties) async {
  final bytes = await File(ncnotePath).readAsBytes();
  late final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    print('  ⚠ Root .ncnote unreadable ($ncnotePath): $e');
    return 0;
  }
  final byName = <String, ArchiveFile>{};
  for (final f in archive.files) {
    byName[f.name] = f;
  }
  var repaired = 0;
  for (final emptyFile in empties) {
    final rel = emptyFile.path.substring(deltaDir.path.length + 1);
    final archiveEntry = byName[rel];
    if (archiveEntry == null) {
      print('  ✗ $rel: not present in .ncnote backup');
      continue;
    }
    final content = archiveEntry.content;
    if (content is! List<int> || content.isEmpty) {
      print('  ✗ $rel: also empty in .ncnote backup');
      continue;
    }
    // Atomic rewrite: tmp + rename so a Nextcloud client mid-sync
    // never sees a half-written file.
    final tmp = '${emptyFile.path}.tmp.repair';
    await File(tmp).writeAsBytes(content);
    await File(tmp).rename(emptyFile.path);
    print('  ✓ $rel: ${content.length} bytes restored from .ncnote');
    repaired++;
  }
  return repaired;
}
