import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/platform/io.dart' as io;
import 'package:abelnotes/core/services/remote_store.dart';

/// What this device last saw of a notebook on one server.
typedef SyncBaseline = ({String? metaEtag, Map<String, String> pageEtags});

/// Pull baselines (meta ETag + page ETags) kept in the notebook's own store
/// folder, so installs sharing the notebooks folder share them. Design and
/// rules: lib/core/sync/README.md, "Pull baselines".
class SyncBaselines {
  SyncBaselines._();

  /// Lives in the store folder; never packaged, uploaded or indexed.
  static const fileName = AppConfig.syncBaselineFile;
  static const _format = 1;
  static const _maxBackends = 4;

  static String metaKey(String id) => 'delta_meta_etag_$id';
  static String pagesKey(String id) => 'page_etags_$id';

  static final Map<String, Future<void>> _locks = {};

  /// Opaque key of [store]'s server+account+root, null when it can't be told
  /// (no remote, Drive offline). Null means: prefs only, as before.
  static Future<String?> identityOf(RemoteStore? store) async {
    if (store == null) return null;
    try {
      final raw = await store
          .baselineIdentity()
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (raw == null || raw.isEmpty) return null;
      return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
    } catch (_) {
      return null;
    }
  }

  static Future<T> _locked<T>(String path, Future<T> Function() body) async {
    final prev = _locks[path];
    final done = Completer<void>();
    _locks[path] = done.future;
    try {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      return await body();
    } finally {
      done.complete();
      if (identical(_locks[path], done.future)) _locks.remove(path);
    }
  }

  static SyncBaseline _fromPrefs(SharedPreferences prefs, String id) {
    final meta = prefs.getString(metaKey(id));
    return (
      metaEtag: meta == null || meta.isEmpty ? null : meta,
      pageEtags: _decodePages(prefs.getString(pagesKey(id))),
    );
  }

  static Map<String, String> _decodePages(Object? raw) {
    try {
      final m = raw is String ? jsonDecode(raw) : raw;
      if (m is! Map) return {};
      return {
        for (final e in m.entries)
          if (e.value is String) e.key as String: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  /// Backends map of the file; empty when missing, corrupt or a newer format.
  static Future<Map<String, dynamic>> _load(String path) async {
    try {
      final f = io.File(path);
      if (!await f.exists()) return {};
      final j = jsonDecode(utf8.decode(await f.readAsBytes()));
      if (j is! Map || j['v'] != _format) return {};
      final b = j['backends'];
      return b is Map ? Map<String, dynamic>.from(b) : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(String path, Map<String, dynamic> backends) async {
    final f = io.File(path);
    if (backends.isEmpty) {
      if (await f.exists()) await f.delete();
      return;
    }
    if (backends.length > _maxBackends) {
      final byAge = backends.keys.toList()
        ..sort((a, b) => _at(backends[b]).compareTo(_at(backends[a])));
      for (final k in byAge.skip(_maxBackends)) {
        backends.remove(k);
      }
    }
    final bytes = utf8.encode(jsonEncode({'v': _format, 'backends': backends}));
    final ts = DateTime.now().microsecondsSinceEpoch;
    final tmp = io.File('$path.$ts-${_seq++}.tmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      try {
        await tmp.rename(path); // replaces the target on every platform
      } on io.FileSystemException {
        // Windows refuses while another process holds the target open; a
        // missing file only means a full pull, never a stale baseline.
        await f.delete();
        await tmp.rename(path);
      }
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static int _seq = 0;

  static int _at(Object? entry) =>
      entry is Map && entry['at'] is int ? entry['at'] as int : 0;

  static Map<String, dynamic> _entry(SyncBaseline b) => {
        if (b.metaEtag != null) 'meta': b.metaEtag,
        'pages': b.pageEtags,
        'at': DateTime.now().millisecondsSinceEpoch,
      };

  static SyncBaseline _parse(Map entry) {
    final meta = entry['meta'];
    return (
      metaEtag: meta is String && meta.isNotEmpty ? meta : null,
      pageEtags: _decodePages(entry['pages']),
    );
  }

  static bool _isEmpty(SyncBaseline b) =>
      b.metaEtag == null && b.pageEtags.isEmpty;

  /// The baseline for [id] on [identity]: the shared file's entry, else this
  /// install's prefs (copied into the file on the way). Never throws.
  static Future<SyncBaseline> read(
      String storeDir, String id, String? identity) async {
    SyncBaseline fromPrefs = (metaEtag: null, pageEtags: <String, String>{});
    try {
      fromPrefs = _fromPrefs(await SharedPreferences.getInstance(), id);
    } catch (_) {}
    if (identity == null) return fromPrefs;
    final path = p.join(storeDir, fileName);
    try {
      return await _locked(path, () async {
        final backends = await _load(path);
        final e = backends[identity];
        if (e is Map) return _parse(e);
        if (!_isEmpty(fromPrefs) && await io.Directory(storeDir).exists()) {
          backends[identity] = _entry(fromPrefs);
          await _save(path, backends);
        }
        return fromPrefs;
      });
    } catch (e) {
      debugPrint('[Baseline] read $id failed: $e');
      return fromPrefs;
    }
  }

  /// Records versions now on disk for [id]. [pageEtags] replaces the map,
  /// [pushedPages] adds to it. Prefs are kept too (older builds, no identity).
  static Future<void> write(
    String storeDir,
    String id,
    String? identity, {
    String? metaEtag,
    Map<String, String>? pageEtags,
    Map<String, String>? pushedPages,
  }) async {
    final meta = metaEtag == null || metaEtag.isEmpty ? null : metaEtag;
    if (meta == null && pageEtags == null && (pushedPages?.isEmpty ?? true)) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (meta != null) await prefs.setString(metaKey(id), meta);
      if (pageEtags != null) {
        await prefs.setString(pagesKey(id), jsonEncode(pageEtags));
      } else if (pushedPages != null && pushedPages.isNotEmpty) {
        final known = _decodePages(prefs.getString(pagesKey(id)));
        await prefs.setString(
            pagesKey(id), jsonEncode({...known, ...pushedPages}));
      }
    } catch (_) {}
    if (identity == null) return;
    final path = p.join(storeDir, fileName);
    try {
      await _locked(path, () async {
        // No store folder: nothing on disk to describe, and creating the
        // folder would turn a library stub into a broken local copy.
        if (!await io.Directory(storeDir).exists()) return;
        final backends = await _load(path);
        final old = backends[identity];
        // No entry yet: start from prefs, which this call already updated.
        final base = old is Map
            ? _parse(old)
            : _fromPrefs(await SharedPreferences.getInstance(), id);
        backends[identity] = _entry((
          metaEtag: meta ?? base.metaEtag,
          pageEtags: pageEtags ?? {...base.pageEtags, ...?pushedPages},
        ));
        await _save(path, backends);
      });
    } catch (e) {
      debugPrint('[Baseline] write $id failed: $e');
    }
  }

  /// Drops [id]'s baseline: [identity]'s entry, or every entry when null.
  static Future<void> forget(
      String storeDir, String id, String? identity) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(metaKey(id));
      await prefs.remove(pagesKey(id));
    } catch (_) {}
    await _forgetFile(p.join(storeDir, fileName), identity);
  }

  static Future<void> _forgetFile(String path, String? identity) async {
    try {
      await _locked(path, () async {
        if (!await io.File(path).exists()) return;
        if (identity == null) {
          await io.File(path).delete();
          return;
        }
        final backends = await _load(path);
        if (backends.remove(identity) != null || backends.isEmpty) {
          await _save(path, backends);
        }
      });
    } catch (e) {
      debugPrint('[Baseline] forget $path failed: $e');
    }
  }

  /// [forget]'s file half for every store under [notebooksRoot].
  static Future<void> forgetEverywhere(
      String notebooksRoot, String? identity) async {
    try {
      final root = io.Directory(notebooksRoot);
      if (!await root.exists()) return;
      final dirs = await root.list().where((e) => e is io.Directory).toList();
      for (final d in dirs) {
        await _forgetFile(p.join(d.path, fileName), identity);
      }
    } catch (e) {
      debugPrint('[Baseline] forget all failed: $e');
    }
  }
}
