import 'dart:convert';
import 'package:abelnotes/core/platform/io.dart';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:abelnotes/core/providers/canvas_provider.dart'
    show decodePageBytes, encodePageBytes;
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Disk persistence of the tray (layout in ../README.md).
class TrayStore {
  final String root;
  TrayStore(this.root);

  static const _version = 1;
  String get _tmp => '$root.tmp';
  String get _old => '$root.old';
  String get _graveyard => '$root.discarded';
  String get _manifest => p.join(root, 'tray.json');

  /// Writes the whole tray, replacing any earlier one; a crash leaves either
  /// the old tray or the new one.
  Future<void> write(PagesTray tray, Map<String, Uint8List> assets) async {
    final tmp = Directory(_tmp);
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    for (var i = 0; i < tray.pages.length; i++) {
      await _file(p.join(_tmp, 'pages', '$i.json'))
          .writeAsBytes(encodePageBytes(tray.pages[i].data), flush: true);
    }
    for (final e in assets.entries) {
      await _file(p.join(_tmp, 'assets', e.key)).writeAsBytes(e.value);
    }
    for (var i = 0; i < tray.thumbs.length; i++) {
      await _file(p.join(_tmp, 'thumbs', '$i.png'))
          .writeAsBytes(tray.thumbs[i]);
    }
    await _file(p.join(_tmp, 'tray.json')).writeAsString(
        jsonEncode(_manifestJson(tray, assets.keys.toList())),
        flush: true);
    final old = Directory(_old);
    if (await old.exists()) await old.delete(recursive: true);
    final cur = Directory(root);
    if (await cur.exists()) await cur.rename(_old);
    await tmp.rename(root);
    if (await old.exists()) await old.delete(recursive: true);
    final g = Directory(_graveyard);
    if (await g.exists()) await g.delete(recursive: true);
  }

  /// Rewrites only the manifest (journal, mode, deleted-source note).
  Future<void> updateManifest(PagesTray tray) async {
    final f = File(_manifest);
    final prev = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final out = _manifestJson(tray, (prev['assetIds'] as List).cast<String>());
    final tmp = File('$_manifest.tmp');
    await tmp.writeAsString(jsonEncode(out), flush: true);
    await tmp.rename(_manifest);
  }

  Map<String, dynamic> _manifestJson(PagesTray t, List<String> assetIds) => {
        'version': _version,
        'id': t.id,
        'mode': t.mode.name,
        'sourceNotebookId': t.sourceNotebookId,
        'sourceTitle': t.sourceTitle,
        'sourceChapterTitle': t.sourceChapterTitle,
        'mixedChapters': t.mixedChapters,
        'sourceDeleted': t.sourceDeleted,
        'journal': t.journal?.toJson(),
        'thumbs': t.thumbs.length,
        'assetIds': assetIds,
        'entries': [for (final pg in t.pages) pg.entry.toJson()],
      };

  /// The saved tray, or null when there is none or it cannot be read.
  Future<PagesTray?> read() async {
    try {
      if (!await Directory(root).exists() && await Directory(_old).exists()) {
        await Directory(_old).rename(root);
      }
      final f = File(_manifest);
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (m['version'] != _version) return null;
      final entries = (m['entries'] as List)
          .map((e) => PageEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      final pages = <TrayPage>[];
      for (var i = 0; i < entries.length; i++) {
        final bytes =
            await File(p.join(root, 'pages', '$i.json')).readAsBytes();
        pages.add(TrayPage(entries[i], decodePageBytes(bytes)));
      }
      final thumbs = <List<int>>[];
      for (var i = 0; i < (m['thumbs'] as int? ?? 0); i++) {
        final tf = File(p.join(root, 'thumbs', '$i.png'));
        if (await tf.exists()) thumbs.add(await tf.readAsBytes());
      }
      return PagesTray(
        id: m['id'] as String,
        mode: TrayMode.values.byName(m['mode'] as String),
        sourceNotebookId: m['sourceNotebookId'] as String,
        sourceTitle: m['sourceTitle'] as String,
        sourceChapterTitle: m['sourceChapterTitle'] as String?,
        mixedChapters: m['mixedChapters'] as bool? ?? false,
        sourceDeleted: m['sourceDeleted'] as bool? ?? false,
        journal: m['journal'] == null
            ? null
            : TrayJournal.fromJson(m['journal'] as Map<String, dynamic>),
        pages: pages,
        thumbs: thumbs,
        saved: true,
      );
    } catch (e) {
      debugPrint('[TrayStore] unreadable tray: $e');
      return null;
    }
  }

  /// Bytes of the assets the tray stored; ids not on disk are absent.
  Future<Map<String, Uint8List>> readAssets(Iterable<String> ids) async {
    final out = <String, Uint8List>{};
    for (final id in ids) {
      final f = File(p.join(root, 'assets', id));
      if (await f.exists()) out[id] = await f.readAsBytes();
    }
    return out;
  }

  /// Moves the tray aside; [restoreDiscarded] can bring it back until
  /// [purgeDiscarded] or the next [write].
  Future<void> discard() async {
    final g = Directory(_graveyard);
    if (await g.exists()) await g.delete(recursive: true);
    if (await Directory(root).exists()) await Directory(root).rename(_graveyard);
  }

  Future<bool> restoreDiscarded() async {
    if (await Directory(root).exists()) return false;
    final g = Directory(_graveyard);
    if (!await g.exists()) return false;
    await g.rename(root);
    return true;
  }

  Future<void> purgeDiscarded() async {
    for (final d in [_graveyard, _tmp, _old]) {
      final dir = Directory(d);
      if (!await dir.exists()) continue;
      // The old copy is only garbage while the live one exists.
      if (d == _old && !await Directory(root).exists()) continue;
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  File _file(String path) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    return f;
  }
}
