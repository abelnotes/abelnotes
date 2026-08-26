import 'dart:typed_data';

import 'package:abelnotes/core/services/remote_store.dart';

/// In-memory [RemoteStore] for tests.
///
/// It doubles as a check on the interface itself: if the sync engine can run
/// against a store with no HTTP, no ETags and no real filesystem, then the
/// abstraction is genuinely backend-neutral and a Drive implementation has a
/// shape to fit into.
class FakeRemoteStore implements RemoteStore {
  FakeRemoteStore({this.basePath = '/AbelNotes/'});

  @override
  final String basePath;

  final Map<String, Uint8List> files = {};
  final Set<String> directories = {};

  /// Every call the engine made, in order — lets a test assert on the commit
  /// ORDER, which is where the sync engine's correctness lives.
  final List<String> calls = [];

  /// Paths that must fail on upload, to exercise half-failed syncs.
  final Set<String> failUploads = {};

  var _version = 0;
  final Map<String, String> _versions = {};

  @override
  Future<void> ensureBaseDirectory() async {
    calls.add('ensureBaseDirectory');
    directories.add(basePath);
  }

  @override
  Future<List<RemoteItem>> listDirectory(String remotePath) async {
    calls.add('list $remotePath');
    if (!directories.contains(remotePath)) {
      throw RemoteStoreException('no such directory: $remotePath', 404);
    }
    final out = <RemoteItem>[];
    for (final dir in directories) {
      if (dir == remotePath) continue;
      if (_parentOf(dir) != remotePath) continue;
      out.add(RemoteItem(path: dir, name: _nameOf(dir), isDirectory: true));
    }
    for (final entry in files.entries) {
      if (_parentOf(entry.key) != remotePath) continue;
      out.add(RemoteItem(
        path: entry.key,
        name: _nameOf(entry.key),
        isDirectory: false,
        contentLength: entry.value.length,
        version: _versions[entry.key],
      ));
    }
    return out;
  }

  @override
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds, bool criticalVerify = false}) async {
    calls.add('download $remotePath');
    final data = files[remotePath];
    if (data == null) {
      throw RemoteStoreException('no such file: $remotePath', 404);
    }
    return data;
  }

  @override
  Future<String?> uploadFile(String remotePath, Uint8List data,
      {int? timeoutSeconds,
      bool criticalVerify = false,
      bool skipVerify = false}) async {
    calls.add('upload $remotePath');
    if (failUploads.contains(remotePath)) {
      throw RemoteStoreException('upload refused: $remotePath', 500);
    }
    files[remotePath] = data;
    return _versions[remotePath] = 'v${++_version}';
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    calls.add('mkdir $remotePath');
    directories.add(remotePath);
  }

  @override
  Future<void> delete(String remotePath) async {
    calls.add('delete $remotePath');
    files.remove(remotePath);
    directories.remove(remotePath);
    files.removeWhere((k, _) => k.startsWith(remotePath));
    directories.removeWhere((d) => d.startsWith(remotePath));
  }

  @override
  Future<({String? version, DateTime? lastModified})?> getFileInfo(
      String remotePath) async {
    calls.add('info $remotePath');
    if (!files.containsKey(remotePath)) return null;
    return (version: _versions[remotePath], lastModified: DateTime(2026));
  }

  @override
  Future<String?> getVersion(String remotePath) async {
    calls.add('version $remotePath');
    return _versions[remotePath];
  }

  @override
  Future<String?> getVersionFast(String remotePath) => getVersion(remotePath);

  @override
  Future<int?> getContentLength(String remotePath) async {
    calls.add('size $remotePath');
    return files[remotePath]?.length;
  }

  static String _parentOf(String path) {
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final cut = trimmed.lastIndexOf('/');
    return cut < 0 ? '' : trimmed.substring(0, cut + 1);
  }

  static String _nameOf(String path) {
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    return trimmed.substring(trimmed.lastIndexOf('/') + 1);
  }
}
