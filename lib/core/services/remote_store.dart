import 'dart:typed_data';

/// One entry in a remote listing.
///
/// Backend-neutral on purpose: WebDAV fills it from a PROPFIND response,
/// Google Drive will fill it from a `files.list` result.
class RemoteItem {
  /// Path as the backend addresses it, relative to the account root.
  final String path;
  final String name;
  final bool isDirectory;
  final int? contentLength;

  /// Opaque token that changes whenever the file's content changes:
  /// the ETag on WebDAV, `md5Checksum` / `headRevisionId` on Drive.
  ///
  /// Compare it for equality, never parse it and never order by it. The sync
  /// engine's whole change detection rests on "different token = different
  /// bytes", which is all any backend guarantees.
  final String? version;
  final DateTime? lastModified;
  final String? contentType;

  RemoteItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.contentLength,
    this.version,
    this.lastModified,
    this.contentType,
  });
}

/// A backend call that failed with a status the engine reasons about.
///
/// The sync engine branches on a few of these — 404 to mean "not there, stop
/// looking", 405 to mean "directory already exists" — so the code cannot be
/// swallowed into a generic error. Backends map their own failures onto HTTP
/// status codes even when they don't speak HTTP: Drive's API already returns
/// them, so the mapping is direct.
class RemoteStoreException implements Exception {
  final String message;
  final int statusCode;

  RemoteStoreException(this.message, this.statusCode);

  @override
  String toString() => 'RemoteStoreException($statusCode): $message';
}

/// The remote is out of space.
///
/// Its own kind because it is the one failure the user can actually do
/// something about, and the one that never fixes itself by waiting: retrying
/// is pointless until they free space or buy more. Drive answers
/// `storageQuotaExceeded`, WebDAV answers 507.
class RemoteStorageFullException extends RemoteStoreException {
  RemoteStorageFullException(super.message, [super.statusCode = 507]);

  @override
  String toString() => 'RemoteStorageFullException: $message';
}

/// The remote side of sync, reduced to what [SyncService] actually calls.
///
/// It exists so a second backend can be added without touching the sync
/// engine, which carries years of hard-won handling of conflicts, ordered
/// commits and half-failed uploads. [WebDavService] is the first
/// implementation; a Drive one comes next.
///
/// Contract notes for anyone writing a new backend:
///
///  * Paths are POSIX-ish strings, directories end in `/`. A backend with no
///    real paths (Drive addresses files by id) is responsible for mapping
///    them, and for keeping that mapping consistent across devices.
///  * [uploadFile] returns the NEW version token when the backend can report
///    one cheaply, else null. Returning null is safe: the engine falls back
///    to reading it back.
///  * Failures throw. Returning a wrong-but-plausible value (empty bytes, a
///    stale version) is far worse than throwing, because the engine's commit
///    order treats a completed call as durable.
abstract class RemoteStore {
  /// Root under which every notebook lives, e.g. `/AbelNotes/`.
  String get basePath;

  /// Creates [basePath] if it isn't there yet. Must be idempotent.
  Future<void> ensureBaseDirectory();

  /// Entries directly under [remotePath]. Throws if it doesn't exist.
  Future<List<RemoteItem>> listDirectory(String remotePath);

  /// Full contents of [remotePath].
  ///
  /// [criticalVerify] asks the backend to be paranoid about truncation on
  /// payloads the engine cannot re-derive — a short read that passes for
  /// success here is silent data loss.
  Future<Uint8List> downloadFile(
    String remotePath, {
    int? timeoutSeconds,
    bool criticalVerify = false,
  });

  /// Writes [data] to [remotePath], returning the new version token if the
  /// backend reports one. [skipVerify] trades the read-back check for speed
  /// on payloads that are cheap to re-upload.
  Future<String?> uploadFile(
    String remotePath,
    Uint8List data, {
    int? timeoutSeconds,
    bool criticalVerify = false,
    bool skipVerify = false,
  });

  /// Idempotent: succeeds if the directory already exists.
  Future<void> createDirectory(String remotePath);

  /// Removes a file or a directory with everything under it.
  Future<void> delete(String remotePath);

  /// Version token + modification time in one round trip, or null if the
  /// file doesn't exist.
  Future<({String? version, DateTime? lastModified})?> getFileInfo(
      String remotePath);

  /// Version token of [remotePath], null if absent or unavailable.
  Future<String?> getVersion(String remotePath);

  /// Same as [getVersion] but allowed to use a cheaper call that some
  /// servers don't support, returning null instead of failing. Backends
  /// with no cheap path may just delegate to [getVersion].
  Future<String?> getVersionFast(String remotePath);

  /// Size in bytes, null if unknown.
  Future<int?> getContentLength(String remotePath);
}
