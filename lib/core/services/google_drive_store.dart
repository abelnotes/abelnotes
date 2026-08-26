import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/remote_store.dart';

/// Supplies an OAuth access token for the Drive calls.
///
/// Kept separate from the store so the sign-in flow (loopback + PKCE on
/// desktop, the platform account picker on Android) can evolve without
/// touching sync, and so tests can hand over a constant string.
abstract class DriveAuth {
  /// A usable access token. [forceRefresh] is set after a 401, meaning the
  /// cached token was rejected and a refresh must actually happen.
  Future<String> accessToken({bool forceRefresh = false});
}

/// [RemoteStore] backed by Google Drive, scope `drive.file`.
///
/// Two things make Drive unlike WebDAV, and both are handled here rather
/// than leaking into the sync engine:
///
///  * **There are no paths.** Drive addresses files by id, and two files in
///    the same folder may share a name. Paths are resolved to ids by walking
///    the folder chain, and the result is memoised in [_idCache] — without
///    it every operation would cost an extra round trip per path segment.
///  * **Writes are rate limited.** The engine uploads every changed page in
///    parallel; against a personal server that is free, against Drive it
///    earns 403s. [_gate] caps how many requests are in flight and
///    [_send] retries the ones Google asks us to slow down, so a burst
///    degrades into "slower" instead of "half-committed".
///
/// The `drive.file` scope only ever shows this app the files it created
/// itself. That is verified behaviour, not an assumption: the grant belongs
/// to the Cloud PROJECT, so the Android and desktop clients of the same
/// project see the same notebooks.
class GoogleDriveStore implements RemoteStore {
  static const _apiRoot = 'https://www.googleapis.com/drive/v3';
  static const _uploadRoot = 'https://www.googleapis.com/upload/drive/v3';
  static const _folderMime = 'application/vnd.google-apps.folder';

  /// Fields worth asking for. Drive returns a minimal object otherwise, and
  /// a second call to learn a file's size costs the same as this.
  static const _fileFields = 'id,name,mimeType,size,md5Checksum,modifiedTime';

  /// Concurrent requests. The engine's own fan-out is unbounded; this is
  /// what stands between it and `userRateLimitExceeded`.
  static const _maxInFlight = 4;

  /// Above this a multipart upload is refused by Drive and the resumable
  /// protocol has to be used instead. A notebook with an imported PDF goes
  /// past it easily, so this is a normal path, not an edge case.
  static const _multipartMaxBytes = 5 * 1024 * 1024;

  /// Attempts per request, including the first. Only rate-limit and 5xx
  /// answers are retried — a 404 is an answer, not a failure to retry.
  static const _maxAttempts = 5;

  final DriveAuth _auth;
  final http.Client _client;

  @override
  final String basePath;

  /// Resolved path -> Drive file id. Cleared for a subtree on delete, since
  /// a stale id would otherwise resurrect a file the user removed.
  final Map<String, String> _idCache = {};

  int _inFlight = 0;
  final _waiting = <Completer<void>>[];
  final _rand = Random();

  GoogleDriveStore(
    this._auth, {
    http.Client? client,
    this.basePath = AppConfig.defaultRemotePath,
  }) : _client = client ?? http.Client();

  // ── RemoteStore ───────────────────────────────────────────────────────

  @override
  Future<void> ensureBaseDirectory() async {
    await _folderId(basePath, createMissing: true);
  }

  @override
  Future<List<RemoteItem>> listDirectory(String remotePath) async {
    final dirPath = _asDir(remotePath);
    final parent = await _folderId(dirPath, createMissing: false);
    if (parent == null) {
      throw RemoteStoreException('no such directory: $remotePath', 404);
    }

    final out = <RemoteItem>[];
    String? pageToken;
    do {
      final res = await _send(() => _get('/files', {
            'q': "'$parent' in parents and trashed = false",
            'fields': 'nextPageToken,files($_fileFields)',
            'pageSize': '1000',
            if (pageToken != null) 'pageToken': pageToken,
          }));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      for (final raw in (body['files'] as List? ?? const [])) {
        final file = raw as Map<String, dynamic>;
        final isDir = file['mimeType'] == _folderMime;
        final name = file['name'] as String;
        final path = isDir ? '$dirPath$name/' : '$dirPath$name';
        _idCache[path] = file['id'] as String;
        out.add(RemoteItem(
          path: path,
          name: name,
          isDirectory: isDir,
          contentLength: int.tryParse(file['size'] as String? ?? ''),
          version: file['md5Checksum'] as String?,
          lastModified: DateTime.tryParse(file['modifiedTime'] as String? ?? ''),
        ));
      }
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null);
    return out;
  }

  @override
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds, bool criticalVerify = false}) async {
    final id = await _fileId(remotePath);
    if (id == null) {
      throw RemoteStoreException('no such file: $remotePath', 404);
    }
    final res = await _send(
      () => _get('/files/$id', {'alt': 'media'}),
      timeoutSeconds: timeoutSeconds,
    );
    final bytes = res.bodyBytes;
    // An empty 200 is a truncated read far more often than a genuinely
    // empty file, and the engine cannot tell the two apart downstream —
    // on a payload it can't re-derive, that silence is data loss. Same
    // reasoning as the WebDAV client's empty-body guard.
    if (bytes.isEmpty) {
      final size = await getContentLength(remotePath);
      if (size != null && size > 0) {
        throw RemoteStoreException(
            'empty body for $remotePath, expected $size bytes', 502);
      }
    }
    return bytes;
  }

  @override
  Future<String?> uploadFile(String remotePath, Uint8List data,
      {int? timeoutSeconds,
      bool criticalVerify = false,
      bool skipVerify = false}) async {
    final parentPath = _parentOf(remotePath);
    final parent = await _folderId(parentPath, createMissing: true);
    if (parent == null) {
      throw RemoteStoreException('cannot create $parentPath', 500);
    }
    final existing = await _fileId(remotePath);
    final name = _nameOf(remotePath);

    // Drive keeps no notion of "overwrite by name": creating twice yields
    // two files with the same name, and the engine would then read whichever
    // came back first. Update when we already know the id.
    final metadata = existing == null
        ? {'name': name, 'parents': [parent]}
        : {'name': name};
    final res = await _send(
      () => data.length > _multipartMaxBytes
          ? _resumableUpload(id: existing, metadata: metadata, data: data)
          : _multipartUpload(id: existing, metadata: metadata, data: data),
      timeoutSeconds: timeoutSeconds,
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _idCache[remotePath] = body['id'] as String;
    return body['md5Checksum'] as String?;
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    await _folderId(_asDir(remotePath), createMissing: true);
  }

  @override
  Future<void> delete(String remotePath) async {
    final id = await _fileId(remotePath) ??
        await _folderId(_asDir(remotePath), createMissing: false);
    if (id == null) return; // already gone: deleting is idempotent
    await _send(() => _request('DELETE', '$_apiRoot/files/$id'));
    _forget(remotePath);
  }

  @override
  Future<({String? version, DateTime? lastModified})?> getFileInfo(
      String remotePath) async {
    final meta = await _metadata(remotePath);
    if (meta == null) return null;
    return (
      version: meta['md5Checksum'] as String?,
      lastModified:
          DateTime.tryParse(meta['modifiedTime'] as String? ?? ''),
    );
  }

  @override
  Future<String?> getVersion(String remotePath) async =>
      (await _metadata(remotePath))?['md5Checksum'] as String?;

  /// Drive has no cheaper metadata call than [getVersion], so this is the
  /// same request. The split exists for WebDAV, where HEAD may or may not
  /// carry an ETag.
  @override
  Future<String?> getVersionFast(String remotePath) => getVersion(remotePath);

  @override
  Future<int?> getContentLength(String remotePath) async {
    final size = (await _metadata(remotePath))?['size'] as String?;
    return size == null ? null : int.tryParse(size);
  }

  // ── Path resolution ───────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _metadata(String remotePath) async {
    final id = await _fileId(remotePath);
    if (id == null) return null;
    final res = await _send(() => _get('/files/$id', {'fields': _fileFields}));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Id of the file at [remotePath], or null when it isn't there.
  Future<String?> _fileId(String remotePath) async {
    final cached = _idCache[remotePath];
    if (cached != null) return cached;
    final parent = await _folderId(_parentOf(remotePath), createMissing: false);
    if (parent == null) return null;
    final id = await _childId(parent, _nameOf(remotePath), folder: false);
    if (id != null) _idCache[remotePath] = id;
    return id;
  }

  /// Id of the folder at [dirPath] (which must end in `/`), creating the
  /// chain when asked. Returns null when it's absent and [createMissing]
  /// is false.
  Future<String?> _folderId(String dirPath,
      {required bool createMissing}) async {
    final cached = _idCache[dirPath];
    if (cached != null) return cached;

    var parentId = 'root';
    var walked = '/';
    for (final segment in dirPath.split('/').where((s) => s.isNotEmpty)) {
      walked = '$walked$segment/';
      final known = _idCache[walked];
      if (known != null) {
        parentId = known;
        continue;
      }
      var id = await _childId(parentId, segment, folder: true);
      if (id == null) {
        if (!createMissing) return null;
        id = await _createFolder(segment, parentId);
      }
      _idCache[walked] = id;
      parentId = id;
    }
    return parentId;
  }

  Future<String?> _childId(String parentId, String name,
      {required bool folder}) async {
    final escaped = name.replaceAll("'", r"\'");
    final res = await _send(() => _get('/files', {
          'q': "'$parentId' in parents and name = '$escaped' "
              "and trashed = false"
              "${folder ? " and mimeType = '$_folderMime'" : ""}",
          'fields': 'files(id)',
          'pageSize': '1',
        }));
    final files = (jsonDecode(res.body) as Map<String, dynamic>)['files']
        as List?;
    if (files == null || files.isEmpty) return null;
    return (files.first as Map<String, dynamic>)['id'] as String;
  }

  Future<String> _createFolder(String name, String parentId) async {
    final res = await _send(() => _request(
          'POST',
          '$_apiRoot/files',
          headers: {'Content-Type': 'application/json'},
          body: utf8.encode(jsonEncode(
              {'name': name, 'mimeType': _folderMime, 'parents': [parentId]})),
        ));
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }

  /// Drops [remotePath] and anything under it from the id cache.
  void _forget(String remotePath) {
    _idCache.remove(remotePath);
    final prefix = _asDir(remotePath);
    _idCache.removeWhere((path, _) => path.startsWith(prefix));
  }

  // ── HTTP ──────────────────────────────────────────────────────────────

  Future<http.Response> _get(String path, Map<String, String> query) =>
      _request('GET', Uri.parse('$_apiRoot$path')
          .replace(queryParameters: query)
          .toString());

  Future<http.Response> _request(String method, String url,
      {Map<String, String>? headers, List<int>? body}) async {
    var res = await _authorized(method, url, headers, body, refresh: false);
    // A 401 means the access token died mid-session — routine, since they
    // last an hour. Renew once and repeat: without this every sync that
    // straddles the expiry would surface as a failure to the user.
    if (res.statusCode == 401) {
      res = await _authorized(method, url, headers, body, refresh: true);
    }
    return res;
  }

  Future<http.Response> _authorized(String method, String url,
      Map<String, String>? headers, List<int>? body,
      {required bool refresh}) async {
    final token = await _auth.accessToken(forceRefresh: refresh);
    final request = http.Request(method, Uri.parse(url))
      ..headers['Authorization'] = 'Bearer $token';
    if (headers != null) request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return http.Response.fromStream(await _client.send(request));
  }

  /// Metadata + bytes in one request, which halves the round trips on the
  /// many small page files a notebook is made of.
  Future<http.Response> _multipartUpload({
    String? id,
    required Map<String, dynamic> metadata,
    required Uint8List data,
  }) async {
    const boundary = 'abelnotes-boundary';
    final head = utf8.encode('--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(metadata)}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/octet-stream\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--');

    final url = id == null
        ? '$_uploadRoot/files?uploadType=multipart&fields=$_fileFields'
        : '$_uploadRoot/files/$id?uploadType=multipart&fields=$_fileFields';
    return _request(
      id == null ? 'POST' : 'PATCH',
      url,
      headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
      body: [...head, ...data, ...tail],
    );
  }

  /// Two-step upload for payloads multipart won't take: ask for a session,
  /// then send the bytes to the URI Drive hands back.
  ///
  /// The bytes go in one PUT rather than in chunks. Chunking only buys
  /// resuming a half-sent upload, and the engine already treats a failed
  /// upload as "not committed" and sends it again — a resume would save
  /// bandwidth but add a second source of truth about what landed.
  Future<http.Response> _resumableUpload({
    String? id,
    required Map<String, dynamic> metadata,
    required Uint8List data,
  }) async {
    final url = id == null
        ? '$_uploadRoot/files?uploadType=resumable&fields=$_fileFields'
        : '$_uploadRoot/files/$id?uploadType=resumable&fields=$_fileFields';
    final start = await _request(
      id == null ? 'POST' : 'PATCH',
      url,
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '${data.length}',
      },
      body: utf8.encode(jsonEncode(metadata)),
    );
    // Hand a failed handshake back untouched: _send decides whether the
    // status is worth another attempt.
    if (start.statusCode < 200 || start.statusCode >= 300) return start;

    final session = start.headers['location'];
    if (session == null) {
      throw RemoteStoreException(
          'resumable upload for ${metadata['name']}: no session URI', 502);
    }
    return _request('PUT', session, body: data);
  }

  /// Runs [call] under the concurrency cap, retrying what Google asks us to
  /// retry and translating everything else into a [RemoteStoreException].
  Future<http.Response> _send(Future<http.Response> Function() call,
      {int? timeoutSeconds}) async {
    await _acquire();
    try {
      Object? lastError;
      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        if (attempt > 0) await Future.delayed(_backoff(attempt));
        try {
          // Same network budget as the WebDAV client: the constant is
          // named for it but is really "how long any sync call may take".
          final res = await call().timeout(Duration(
              seconds: timeoutSeconds ?? AppConfig.webdavTimeoutSeconds));
          if (res.statusCode >= 200 && res.statusCode < 300) return res;
          final reason = _reason(res);
          // Out of space is not a transient failure: the four retries below
          // would just cost the user four more seconds before the same
          // answer, and the app has something specific to say about it.
          if (reason.contains('storageQuotaExceeded')) {
            throw RemoteStorageFullException(
                'drive ${res.statusCode}: $reason', res.statusCode);
          }
          if (_isRetryable(res)) {
            lastError = RemoteStoreException(
                'drive ${res.statusCode}: $reason', res.statusCode);
            continue;
          }
          throw RemoteStoreException(
              'drive ${res.statusCode}: $reason', res.statusCode);
        } on RemoteStoreException {
          rethrow;
        } catch (e) {
          // Network-level failure: worth another attempt.
          lastError = e;
        }
      }
      if (lastError is RemoteStoreException) throw lastError;
      throw RemoteStoreException('drive request failed: $lastError', 503);
    } finally {
      _release();
    }
  }

  /// 429 and 5xx are always worth another go. A 403 is only retryable when
  /// its reason is a rate limit — a 403 for insufficient permission would
  /// loop forever otherwise.
  static bool _isRetryable(http.Response res) {
    if (res.statusCode == 429 || res.statusCode >= 500) return true;
    if (res.statusCode != 403) return false;
    final reason = _reason(res);
    return reason.contains('rateLimitExceeded') ||
        reason.contains('userRateLimitExceeded') ||
        reason.contains('backendError');
  }

  static String _reason(http.Response res) {
    try {
      final error = (jsonDecode(res.body) as Map<String, dynamic>)['error'];
      if (error is Map<String, dynamic>) {
        final errors = error['errors'];
        final first = errors is List && errors.isNotEmpty
            ? errors.first as Map<String, dynamic>
            : const <String, dynamic>{};
        return '${first['reason'] ?? ''} ${error['message'] ?? ''}'.trim();
      }
    } catch (_) {}
    return res.body.length > 200 ? res.body.substring(0, 200) : res.body;
  }

  /// Exponential with jitter: a whole notebook's pages hit the limit at the
  /// same instant, and retrying them in lockstep just rebuilds the burst.
  Duration _backoff(int attempt) => Duration(
      milliseconds: (250 * pow(2, attempt - 1)).round() + _rand.nextInt(250));

  Future<void> _acquire() async {
    if (_inFlight < _maxInFlight) {
      _inFlight++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
      return;
    }
    _inFlight--;
  }

  // ── Path helpers ──────────────────────────────────────────────────────

  static String _asDir(String path) => path.endsWith('/') ? path : '$path/';

  static String _parentOf(String path) {
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final cut = trimmed.lastIndexOf('/');
    return cut < 0 ? '/' : trimmed.substring(0, cut + 1);
  }

  static String _nameOf(String path) {
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    return trimmed.substring(trimmed.lastIndexOf('/') + 1);
  }
}
