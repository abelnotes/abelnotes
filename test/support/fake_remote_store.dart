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
  Future<void> rename(String fromPath, String toPath) async {
    calls.add('rename $fromPath $toPath');
    if (files.containsKey(toPath)) {
      throw RemoteStoreException('rename target exists: $toPath', 412);
    }
    final data = files.remove(fromPath);
    if (data == null) throw RemoteStoreException('no such file: $fromPath', 404);
    files[toPath] = data;
    final v = _versions.remove(fromPath);
    if (v != null) _versions[toPath] = v;
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

  /// Called just before a conditional upload checks its precondition: lets a
  /// test play "another device wrote in between".
  void Function(String path)? beforeConditionalCheck;

  /// Gives [path] a new version, as any write by someone else would.
  void bumpVersion(String path) => _versions[path] = 'v${++_version}';

  @override
  Future<String?> uploadFileConditional(String remotePath, Uint8List data,
      {String? ifMatchVersion, bool ifAbsent = false, int? timeoutSeconds}) async {
    calls.add('upload-if $remotePath');
    beforeConditionalCheck?.call(remotePath);
    final exists = files.containsKey(remotePath);
    // If-Match on a file that is gone fails too, as on a real server.
    if ((ifAbsent && exists) ||
        (ifMatchVersion != null &&
            (!exists || _versions[remotePath] != ifMatchVersion))) {
      throw RemoteStoreException('precondition failed: $remotePath', 412);
    }
    return uploadFile(remotePath, data);
  }

  @override
  Future<String?> uploadFileAtomic(String remotePath, Uint8List data,
      {String? ifMatchVersion, int? timeoutSeconds}) async {
    calls.add('${ifMatchVersion == null ? 'upload-atomic' : 'upload-atomic-if'} '
        '$remotePath');
    if (ifMatchVersion != null) {
      beforeConditionalCheck?.call(remotePath);
      if (!files.containsKey(remotePath) ||
          _versions[remotePath] != ifMatchVersion) {
        throw RemoteStoreException('precondition failed: $remotePath', 412);
      }
    }
    return uploadFile(remotePath, data);
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
  bool get nullVersionMeansAbsent => true;

  @override
  Future<String?> getVersion(String remotePath) async {
    calls.add('version $remotePath');
    return files.containsKey(remotePath) ? _versions[remotePath] : null;
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
