// Web replacement for the slice of `dart:io` the app uses for local storage.
//
// The whole tree lives in memory (so the synchronous File API keeps working)
// and every mutation is written through to IndexedDB, which is what makes
// notebooks survive a reload and stay readable offline. Platform checks all
// answer "no", so desktop/mobile-only branches are skipped on the web.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:web/web.dart' as web;

import 'package:abelnotes/core/platform/io.dart' as io;

export 'dart:io'
    hide File, Directory, Platform, FileSystemEntity, FileStat, Link;

// ───────────────────────── Platform ─────────────────────────

class Platform {
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isMacOS = false;
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isFuchsia = false;
  static const String pathSeparator = '/';
  static const String operatingSystem = 'web';
  static const String resolvedExecutable = '';
  static const Map<String, String> environment = <String, String>{};
}

// ───────────────────────── Virtual store ─────────────────────────

class _Entry {
  _Entry(this.bytes, this.modified);
  Uint8List bytes;
  DateTime modified;
}

/// In-memory tree + IndexedDB write-through. Call [WebFs.init] once at
/// startup, before anything touches a [File] or [Directory].
class WebFs {
  WebFs._();
  static final WebFs instance = WebFs._();

  static const _dbName = 'abelnotes_fs';
  static const _store = 'entries';

  final Map<String, _Entry> files = {};
  final Set<String> dirs = {};
  web.IDBDatabase? _db;
  Future<void> _writes = Future.value();

  /// Last IndexedDB write failure (e.g. QuotaExceededError). The in-memory
  /// tree still has the data, but it won't survive a reload.
  final ValueNotifier<String?> persistError = ValueNotifier(null);

  static Future<void> init() => instance._init();

  Future<void> _init() async {
    if (_db != null) return;
    final factory = web.window.indexedDB;
    final req = factory.open(_dbName, 1);
    req.onupgradeneeded = ((web.Event _) {
      final db = req.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) {
        db.createObjectStore(_store);
      }
    }).toJS;
    _db = await _await<web.IDBDatabase>(req);

    final tx = _db!.transaction(_store.toJS, 'readonly');
    final cursorReq = tx.objectStore(_store).openCursor();
    final done = Completer<void>();
    cursorReq.onsuccess = ((web.Event _) {
      final cursor = cursorReq.result as web.IDBCursorWithValue?;
      if (cursor == null) {
        done.complete();
        return;
      }
      final key = (cursor.key as JSString).toDart;
      final value = cursor.value as JSObject;
      if (key.startsWith('d:')) {
        dirs.add(key.substring(2));
      } else if (key.startsWith('f:')) {
        final b = value['b'] as JSUint8Array;
        final m = (value['m'] as JSNumber).toDartInt;
        files[key.substring(2)] =
            _Entry(b.toDart, DateTime.fromMillisecondsSinceEpoch(m));
      }
      cursor.continue_();
    }).toJS;
    cursorReq.onerror = ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    await done.future;

    // Ask the browser not to evict the store under storage pressure. Not
    // awaited: Firefox holds the answer until the user replies to its prompt.
    try {
      unawaited(web.window.navigator.storage
          .persist()
          .toDart
          .then((_) {}, onError: (Object _) {}));
    } catch (_) {}
  }

  Future<T> _await<T extends JSAny?>(web.IDBRequest req) {
    final c = Completer<T>();
    req.onsuccess = ((web.Event _) => c.complete(req.result as T)).toJS;
    req.onerror = ((web.Event _) =>
        c.completeError(io.FileSystemException('IndexedDB error'))).toJS;
    return c.future;
  }

  void _persist(void Function(web.IDBObjectStore s) op) {
    final db = _db;
    if (db == null) return;
    _writes = _writes.then((_) {
      final c = Completer<void>();
      final tx = db.transaction(_store.toJS, 'readwrite');
      tx.oncomplete = ((web.Event _) => c.complete()).toJS;
      void failed(web.Event _) {
        persistError.value = tx.error?.name ?? 'transaction aborted';
        print('[WebFs] IndexedDB write failed: ${persistError.value}');
        if (!c.isCompleted) c.complete();
      }
      tx.onerror = failed.toJS;
      tx.onabort = failed.toJS;
      op(tx.objectStore(_store));
      return c.future;
    }).catchError((Object e) {
      // A throw here must not poison the chain: every later write would be skipped.
      persistError.value = '$e';
      print('[WebFs] IndexedDB write failed: $e');
    });
  }

  void _putFile(String path, _Entry e) => _persist((s) {
        final o = JSObject();
        o['b'] = e.bytes.toJS;
        o['m'] = e.modified.millisecondsSinceEpoch.toJS;
        s.put(o, 'f:$path'.toJS);
      });

  void _putDir(String path) =>
      _persist((s) => s.put(JSObject(), 'd:$path'.toJS));

  void _del(String key) => _persist((s) => s.delete(key.toJS));

  // ── Path helpers ──

  static String norm(String path) {
    final parts = <String>[];
    for (final seg in path.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    return '/${parts.join('/')}';
  }

  static String parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  bool dirExists(String path) {
    if (path == '/' || dirs.contains(path)) return true;
    final prefix = '$path/';
    return files.keys.any((k) => k.startsWith(prefix)) ||
        dirs.any((d) => d.startsWith(prefix));
  }

  void mkdirs(String path) {
    var cur = path;
    while (cur != '/' && dirs.add(cur)) {
      _putDir(cur);
      cur = parentOf(cur);
    }
  }

  void writeFile(String path, Uint8List bytes) {
    mkdirs(parentOf(path));
    final e = _Entry(bytes, DateTime.now());
    files[path] = e;
    _putFile(path, e);
  }

  void deleteFile(String path) {
    if (files.remove(path) != null) _del('f:$path');
  }

  void deleteTree(String path) {
    final prefix = '$path/';
    for (final k in files.keys.where((k) => k.startsWith(prefix)).toList()) {
      deleteFile(k);
    }
    for (final d
        in dirs.where((d) => d == path || d.startsWith(prefix)).toList()) {
      dirs.remove(d);
      _del('d:$d');
    }
  }

  void moveTree(String from, String to) {
    final prefix = '$from/';
    for (final k in files.keys.where((k) => k.startsWith(prefix)).toList()) {
      final e = files[k]!;
      deleteFile(k);
      final nk = '$to/${k.substring(prefix.length)}';
      files[nk] = e;
      _putFile(nk, e);
    }
    for (final d
        in dirs.where((d) => d == from || d.startsWith(prefix)).toList()) {
      dirs.remove(d);
      _del('d:$d');
      final nd = d == from ? to : '$to/${d.substring(prefix.length)}';
      dirs.add(nd);
      _putDir(nd);
    }
    mkdirs(to);
  }
}

// ───────────────────────── Entities ─────────────────────────

class FileStat {
  FileStat._(this.size, this.modified, this.exists);
  final int size;
  final DateTime modified;
  final bool exists;
  io.FileSystemEntityType get type =>
      exists ? io.FileSystemEntityType.file : io.FileSystemEntityType.notFound;
}

abstract class FileSystemEntity {
  FileSystemEntity(String path) : path = WebFs.norm(path);
  final String path;

  Directory get parent => Directory(WebFs.parentOf(path));
  FileSystemEntity get absolute => this;
  Uri get uri => Uri.file(path);

  WebFs get _fs => WebFs.instance;

  Future<FileSystemEntity> delete({bool recursive = false});
  void deleteSync({bool recursive = false});

  static bool isDirectorySync(String path) =>
      WebFs.instance.dirExists(WebFs.norm(path));
  static bool isFileSync(String path) =>
      WebFs.instance.files.containsKey(WebFs.norm(path));
  static Future<bool> isDirectory(String path) async => isDirectorySync(path);
  static Future<bool> isFile(String path) async => isFileSync(path);
}

class File extends FileSystemEntity {
  File(super.path);

  @override
  File get absolute => this;

  _Entry? get _e => _fs.files[path];

  Future<bool> exists() async => existsSync();
  bool existsSync() => _e != null;

  Future<int> length() async => lengthSync();
  int lengthSync() => _need().bytes.length;

  Future<DateTime> lastModified() async => _need().modified;
  DateTime lastModifiedSync() => _need().modified;

  Future<FileStat> stat() async => statSync();
  FileStat statSync() {
    final e = _e;
    return e == null
        ? FileStat._(-1, DateTime.fromMillisecondsSinceEpoch(0), false)
        : FileStat._(e.bytes.length, e.modified, true);
  }

  _Entry _need() {
    final e = _e;
    if (e == null) {
      throw io.PathNotFoundException(path, const io.OSError('Not found', 2));
    }
    return e;
  }

  Future<Uint8List> readAsBytes() async => readAsBytesSync();
  // Match dart:io's caller-owned read buffer. ZIP entries can be views into
  // an archive; Flutter's Firefox image-decoder fallback consumes .buffer,
  // so returning that view would decode the whole ZIP instead of the asset.
  Uint8List readAsBytesSync() => Uint8List.fromList(_need().bytes);

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);
  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(_need().bytes);

  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      const LineSplitter().convert(readAsStringSync(encoding: encoding));

  Future<File> writeAsBytes(List<int> bytes,
      {io.FileMode mode = io.FileMode.write, bool flush = false}) async {
    writeAsBytesSync(bytes, mode: mode);
    return this;
  }

  void writeAsBytesSync(List<int> bytes,
      {io.FileMode mode = io.FileMode.write, bool flush = false}) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (mode == io.FileMode.append && _e != null) {
      final old = _e!.bytes;
      final merged = Uint8List(old.length + data.length)
        ..setRange(0, old.length, old)
        ..setRange(old.length, old.length + data.length, data);
      _fs.writeFile(path, merged);
    } else {
      _fs.writeFile(path, data);
    }
  }

  Future<File> writeAsString(String contents,
      {io.FileMode mode = io.FileMode.write,
      Encoding encoding = utf8,
      bool flush = false}) async {
    writeAsBytesSync(encoding.encode(contents), mode: mode);
    return this;
  }

  void writeAsStringSync(String contents,
          {io.FileMode mode = io.FileMode.write,
          Encoding encoding = utf8,
          bool flush = false}) =>
      writeAsBytesSync(encoding.encode(contents), mode: mode);

  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    createSync();
    return this;
  }

  void createSync({bool recursive = false, bool exclusive = false}) {
    if (_e == null) _fs.writeFile(path, Uint8List(0));
  }

  Future<File> rename(String newPath) async {
    final e = _need();
    final dest = WebFs.norm(newPath);
    _fs.deleteFile(path);
    _fs.mkdirs(WebFs.parentOf(dest));
    _fs.files[dest] = e;
    _fs._putFile(dest, e);
    return File(dest);
  }

  Future<File> copy(String newPath) async {
    final e = _need();
    final dest = WebFs.norm(newPath);
    _fs.writeFile(dest, Uint8List.fromList(e.bytes));
    return File(dest);
  }

  Future<File> delete({bool recursive = false}) async {
    deleteSync();
    return this;
  }

  void deleteSync({bool recursive = false}) {
    _need();
    _fs.deleteFile(path);
  }

  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.value(_need().bytes.sublist(start ?? 0, end));
}

class Directory extends FileSystemEntity {
  Directory(super.path);

  static Directory get systemTemp => Directory('/tmp');
  static Directory get current => Directory('/');

  @override
  Directory get absolute => this;

  Future<bool> exists() async => existsSync();
  bool existsSync() => _fs.dirExists(path);

  Future<Directory> create({bool recursive = false}) async {
    createSync(recursive: recursive);
    return this;
  }

  void createSync({bool recursive = false}) => _fs.mkdirs(path);

  Future<Directory> createTemp([String? prefix]) async {
    final d = Directory(
        '$path/${prefix ?? ''}${DateTime.now().microsecondsSinceEpoch}');
    d.createSync();
    return d;
  }

  Future<Directory> rename(String newPath) async {
    final dest = WebFs.norm(newPath);
    _fs.moveTree(path, dest);
    return Directory(dest);
  }

  Future<Directory> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  void deleteSync({bool recursive = false}) => _fs.deleteTree(path);

  List<FileSystemEntity> listSync(
      {bool recursive = false, bool followLinks = true}) {
    final prefix = path == '/' ? '/' : '$path/';
    final out = <FileSystemEntity>[];
    final seenDirs = <String>{};
    for (final k in _fs.files.keys) {
      if (!k.startsWith(prefix)) continue;
      final rest = k.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        out.add(File(k));
      } else if (recursive) {
        out.add(File(k));
      }
      if (slash >= 0) seenDirs.add('$prefix${rest.substring(0, slash)}');
    }
    for (final d in _fs.dirs) {
      if (!d.startsWith(prefix)) continue;
      final rest = d.substring(prefix.length);
      if (rest.isEmpty) continue;
      final slash = rest.indexOf('/');
      if (slash < 0 || recursive) seenDirs.add(d);
      if (slash >= 0) seenDirs.add('$prefix${rest.substring(0, slash)}');
    }
    if (recursive) {
      // every intermediate directory under a file
      for (final k in _fs.files.keys.where((k) => k.startsWith(prefix))) {
        var cur = WebFs.parentOf(k);
        while (cur.length > prefix.length) {
          seenDirs.add(cur);
          cur = WebFs.parentOf(cur);
        }
      }
    }
    out.addAll(seenDirs.map(Directory.new));
    return out;
  }

  Stream<FileSystemEntity> list(
          {bool recursive = false, bool followLinks = true}) =>
      Stream.fromIterable(listSync(recursive: recursive));
}
