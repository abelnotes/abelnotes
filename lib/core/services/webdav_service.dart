import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:xml/xml.dart';
import 'package:abelnotes/config/app_config.dart';

/// Tipo di server WebDAV a cui si è connessi.
///
/// Cambia solo due cose: come si costruisce l'URL DAV (Nextcloud/ownCloud
/// hanno il pattern `remote.php/dav/files/<user>`, un server generico riceve
/// l'URL DAV completo dall'utente) e la disponibilità della condivisione
/// via OCS (solo Nextcloud/ownCloud). Tutto il resto del protocollo è
/// WebDAV standard e identico.
enum WebDavServerType {
  /// Nextcloud oppure ownCloud (stesso endpoint DAV e stessa OCS Share API).
  nextcloud,

  /// Server WebDAV generico (Seafile, Synology, Apache mod_dav, rclone,
  /// Hetzner Storage Box…): l'utente fornisce l'URL DAV completo.
  generic;

  static WebDavServerType fromName(String? name) =>
      name == generic.name ? generic : nextcloud;
}

/// Informazioni su un file/cartella remoto WebDAV.
class WebDavItem {
  final String path;
  final String name;
  final bool isDirectory;
  final int? contentLength;
  final String? etag;
  final DateTime? lastModified;
  final String? contentType;

  WebDavItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.contentLength,
    this.etag,
    this.lastModified,
    this.contentType,
  });
}

/// Client WebDAV per connessione diretta a Nextcloud.
///
/// Supporta: PROPFIND (listing), GET (download), PUT (upload),
/// MKCOL (crea cartella), DELETE.
class WebDavService {
  /// Parallel-connection limit per host.
  ///
  /// Dart's default `HttpClient.maxConnectionsPerHost` is 6 — matching the
  /// old HTTP/1.1 browser convention.  For a delta pull that fires 30
  /// page downloads with `Future.wait`, that means 6 active + 24 queued
  /// and the whole batch takes ceil(30/6) = 5 RTTs minimum instead of 1.
  ///
  /// Bumping to 16 gives a solid 2–3× speedup on parallel pulls on both
  /// desktop (low RTT, CPU-bound) and mobile/Tailscale (higher RTT,
  /// latency-bound) without overwhelming a typical Nextcloud server.
  /// Raising further hits diminishing returns (server-side worker pool
  /// + TCP slow-start dominate).
  /// Cap on simultaneously-open TCP connections per host. Was 16 — fine
  /// on a clean LAN, but on Tailscale a 16-wide fan-out tends to make
  /// the relay drop connections silently, and then ALL 16 slots are
  /// stale at once when the app does a parallel pull. 6 keeps enough
  /// parallelism for the per-page batch without overwhelming the relay.
  static const int _maxConnectionsPerHost = 6;

  /// How long an idle connection is held open before the client drops it.
  /// Longer keep-alive means fewer TCP+TLS handshakes during the 4-second
  /// polling loop; too long and mobile OSes start complaining about
  /// battery.
  /// How long to keep an idle TCP connection in the pool. Was 45 s —
  /// longer than the ~30 s NAT/keep-alive that Tailscale middleboxes
  /// often enforce, so the next request on a 30-45 s idle connection
  /// failed with "Connection closed before full header was received".
  /// 20 s is shorter than any common middlebox timeout while still
  /// amortising the TLS handshake across back-to-back requests.
  static const Duration _idleTimeout = Duration(seconds: 20);

  final String serverUrl;
  final String username;
  final String password;
  final String basePath;
  final WebDavServerType serverType;

  /// SHA-256 fingerprint (hex) of the certificate last accepted for this
  /// server's host. Null means "not pinned yet" — trust-on-first-use
  /// applies. Mutable: updated in-memory the moment TOFU fires, so a
  /// MITM attempt later in the same session (after the legitimate first
  /// connection) is rejected too, not just on the next app launch.
  String? pinnedCertFingerprint;

  /// Fired once, the first time a certificate is pinned for this server —
  /// the caller (auth_provider) persists it so future launches pin against
  /// it from the start instead of re-trusting on first use every time.
  final void Function(String fingerprint)? onCertificatePinned;

  /// Set when the server presented a certificate that does NOT match
  /// [pinnedCertFingerprint] (as opposed to "no pin yet" — see
  /// [_badCertificateCallback]). Callers use this to show a distinct
  /// "server certificate changed" message instead of a generic connection
  /// error, and to point the user at the manual re-trust flow in Settings.
  bool certificateMismatchDetected = false;

  /// The fingerprint the server actually presented, when it didn't match
  /// the pinned one. Null unless [certificateMismatchDetected] is true.
  String? rejectedCertFingerprint;

  late final String _davUrl;
  late final Map<String, String> _authHeaders;
  late http.Client _client;
  late io.HttpClient _innerHttpClient;

  /// Counter of consecutive request failures (timeout, IO error, null
  /// response where we expected content). When this exceeds
  /// [_zombieClientThreshold] we rebuild the underlying HttpClient — on
  /// iOS the NSURLSession backing dart:io can occasionally get into a
  /// state where EVERY outbound call returns null/empty even though the
  /// network itself is healthy (verified by Safari), and only a fresh
  /// session fixes it. Resets on every successful request.
  int _consecutiveFailures = 0;
  /// Stale-pool failures (Connection closed / reset) trip the rebuild
  /// after a single occurrence — these are a near-perfect signal that
  /// the kept-alive connection was dropped server-side and reusing it
  /// will fail again. Other errors (timeout, 5xx) still need the usual
  /// 3-strike confirmation.
  static const int _zombieClientThreshold = 3;
  static const int _staleConnectionThreshold = 1;
  DateTime _lastClientBuildAt = DateTime.now();
  /// Minimum time between rebuilds. Old value was 20 s, which let the
  /// in-flight batch (8+ parallel page GETs) burn 30-60 failures on
  /// stale pool connections before the next rebuild was allowed. 3 s
  /// is enough to avoid a tight reconnect loop on a real server outage,
  /// but short enough that a fresh stale-pool detection rebuilds
  /// immediately instead of accumulating cascading failures.
  static const Duration _clientRebuildCooldown = Duration(seconds: 3);

  WebDavService({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.basePath = AppConfig.defaultRemotePath,
    this.serverType = WebDavServerType.nextcloud,
    this.pinnedCertFingerprint,
    this.onCertificatePinned,
  }) {
    // Warn if not using HTTPS (credentials travel in plaintext over HTTP)
    final uri = Uri.parse(serverUrl);
    if (uri.scheme != 'https') {
      // ignore: avoid_print
      print('[WebDAV] WARNING: Connection uses HTTP — credentials are not encrypted. '
          'Consider switching to HTTPS.');
    }

    final cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    _davUrl = switch (serverType) {
      // Nextcloud/ownCloud: endpoint DAV standard derivato da URL istanza.
      WebDavServerType.nextcloud => '$cleanUrl/remote.php/dav/files/$username',
      // Generico: l'utente ha già fornito l'URL DAV completo (es.
      // `https://nas:5006/home`, `https://server/seafdav`).
      WebDavServerType.generic => cleanUrl,
    };

    final credentials = base64Encode(utf8.encode('$username:$password'));
    _authHeaders = {
      'Authorization': 'Basic $credentials',
      // Explicit gzip request so Nextcloud's mod_deflate compresses the
      // JSON page payloads on the wire — typical compression ratio for
      // stroke JSON is 5-10× so this is a significant bandwidth saving
      // on slower links (Tailscale over cellular).  Dart's HttpClient
      // auto-decompresses gzip responses by default.
      'Accept-Encoding': 'gzip',
    };

    _buildClient();

    // Pre-warm the connection pool in the background so the very first
    // pull on app-start doesn't pay the TCP handshake / TLS ALPN cost
    // inside the user's "Apertura notebook..." dialog.  Fire-and-forget;
    // a failure here just means the first real request pays the cost.
    // ignore: discarded_futures
    _preWarm();
  }

  void _buildClient() {
    // Tear down any previous HttpClient (on reconnect / zombie recovery).
    try { _client.close(); } catch (_) {}
    _innerHttpClient = io.HttpClient()
      ..maxConnectionsPerHost = _maxConnectionsPerHost
      ..idleTimeout = _idleTimeout
      ..autoUncompress = true
      ..badCertificateCallback = _badCertificateCallback;
    _client = http_io.IOClient(_innerHttpClient);
    _lastClientBuildAt = DateTime.now();
    _consecutiveFailures = 0;
  }

  /// Record a request outcome. On repeated failure, rebuild the underlying
  /// HttpClient to recover from an iOS NSURLSession that has silently
  /// gone zombie (Safari works, dart:io returns null for every call).
  void _recordSuccess() {
    if (_consecutiveFailures > 0) {
      // ignore: avoid_print
      print('[WebDAV] Recovered after $_consecutiveFailures consecutive failures');
    }
    _consecutiveFailures = 0;
  }

  void _recordFailure(String op, Object error) {
    _consecutiveFailures++;
    // "Connection closed" / "Connection reset" / "broken pipe" are
    // almost always pool-stale: the kept-alive socket was dropped
    // server-side (middlebox NAT timeout, Tailscale relay churn) and
    // every subsequent attempt on the same pool will fail the same
    // way until we tear it down. Trip rebuild after a single one of
    // these instead of waiting for the 3-strike confirmation; that
    // was what let 30-60 cascading failures accumulate during a
    // parallel page batch.
    final errStr = error.toString().toLowerCase();
    final isStaleConnection = errStr.contains('connection closed') ||
        errStr.contains('connection reset') ||
        errStr.contains('broken pipe') ||
        errStr.contains('connection terminated');
    final threshold =
        isStaleConnection ? _staleConnectionThreshold : _zombieClientThreshold;
    final sinceBuild = DateTime.now().difference(_lastClientBuildAt);
    if (_consecutiveFailures >= threshold &&
        sinceBuild > _clientRebuildCooldown) {
      // ignore: avoid_print
      print('[WebDAV] Rebuilding HttpClient after $_consecutiveFailures '
          'consecutive failures on $op '
          '(${isStaleConnection ? "stale-pool" : "generic"}): $error');
      _buildClient();
      // fire-and-forget pre-warm on the fresh client
      // ignore: discarded_futures
      _preWarm();
    }
  }

  /// Force-rebuild the HttpClient. Call this when connectivity is known
  /// to have transitioned offline→online (iOS can leave NSURLSession
  /// stranded after a Tailscale/WiFi handoff; Safari works but our
  /// dart:io client keeps returning null). The rebuild cooldown is
  /// bypassed because the caller has external evidence of a transition.
  void wakeUp() {
    // ignore: avoid_print
    print('[WebDAV] wakeUp() — rebuilding HttpClient on external trigger');
    _buildClient();
    // ignore: discarded_futures
    _preWarm();
  }

  /// Trust-on-first-use certificate pinning, scoped to the server host the
  /// user configured. Self-hosted Nextcloud instances routinely run
  /// self-signed certs (no public CA), so we can't require normal chain
  /// validation — but blindly trusting ANY certificate for that host (the
  /// old behaviour) means a man-in-the-middle only has to intercept traffic
  /// to silently harvest WebDAV credentials, indefinitely. Pinning the exact
  /// certificate seen on first contact and rejecting anything else for that
  /// host closes that gap: an attacker now has to be positioned for the
  /// very first connection specifically, and every later mismatch (a real
  /// MITM, or the server's cert legitimately changing) surfaces as a
  /// connection failure instead of silently succeeding.
  bool _badCertificateCallback(io.X509Certificate cert, String host, int port) {
    final configured = Uri.parse(serverUrl);
    if (host != configured.host || configured.scheme != 'https') return false;

    final fingerprint = sha256.convert(cert.der).toString();
    final pinned = pinnedCertFingerprint;
    if (pinned == null) {
      pinnedCertFingerprint = fingerprint;
      onCertificatePinned?.call(fingerprint);
      return true;
    }
    if (fingerprint == pinned) return true;
    // Mismatch: never silently re-pin. Reject the connection and let the
    // caller surface a "server certificate changed" message with a manual
    // re-trust path, instead of a generic network error.
    certificateMismatchDetected = true;
    rejectedCertFingerprint = fingerprint;
    return false;
  }

  /// One-off TLS probe: connects to [serverUrl]'s host:port and returns the
  /// SHA-256 fingerprint of whatever certificate the server presents right
  /// now, WITHOUT trusting or pinning anything. Purely so a caller can show
  /// it to the user for out-of-band confirmation — the "authenticity of
  /// host can't be established" moment, same model as SSH — before any real
  /// WebDAV request (credentials included) goes over this connection.
  ///
  /// Returns null for non-HTTPS servers (nothing to pin) or if the TCP/TLS
  /// connection itself fails; callers fall back to their normal
  /// connection-error handling in that case.
  static Future<String?> probeCertificateFingerprint(String serverUrl) async {
    final uri = Uri.parse(serverUrl);
    if (uri.scheme != 'https') return null;
    final port = uri.hasPort ? uri.port : 443;
    io.SecureSocket? socket;
    try {
      socket = await io.SecureSocket.connect(
        uri.host,
        port,
        onBadCertificate: (_) => true, // inspecting only, not trusting yet
        timeout: const Duration(seconds: 10),
      );
      final cert = socket.peerCertificate;
      if (cert == null) return null;
      return sha256.convert(cert.der).toString();
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// Formats a raw SHA-256 hex fingerprint as colon-separated byte pairs
  /// (`AB:CD:EF:...`), the conventional readable form for out-of-band
  /// fingerprint comparison (same style `ssh-keygen -lf` / browsers use).
  static String formatFingerprint(String hex) {
    final upper = hex.toUpperCase();
    final pairs = <String>[
      for (var i = 0; i < upper.length; i += 2)
        upper.substring(i, i + 2 > upper.length ? upper.length : i + 2),
    ];
    return pairs.join(':');
  }

  Future<void> _preWarm() async {
    try {
      final r = await _client
          .head(Uri.parse(_fullUrl('/')), headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      // Drain to release connection back to the pool.
      // ignore: avoid_print
      print('[WebDAV] Connection pre-warmed (status ${r.statusCode})');
    } catch (_) {
      // Silently ignore — first real request will retry with normal timeout.
    }
  }

  /// Drain and discard the body of a [http.StreamedResponse] we don't read.
  /// An unlistened response stream never returns its socket to the pool
  /// (max [_maxConnectionsPerHost] per host), eventually starving later
  /// requests and tripping the zombie-client detector.
  void _drainStream(http.StreamedResponse response) {
    unawaited(response.stream.drain<void>().catchError((_) {}));
  }

  /// URL completo per un path remoto.
  ///
  /// Ogni segmento è percent-encoded: senza, un `#` o `?` nel nome file
  /// tronca l'URL in fragment/query (il PUT finisce su un file sbagliato)
  /// e un `%` letterale viene reinterpretato come escape (`50%20.pdf`
  /// verrebbe richiesto come `50 .pdf`). Gli slash separano i segmenti e
  /// restano intatti; i path in ingresso sono SEMPRE decodati (i consumer
  /// usano `WebDavItem.name`, già decodato, o path locali puliti).
  String _fullUrl(String remotePath) {
    final cleanPath = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    final encoded = cleanPath.split('/').map(Uri.encodeComponent).join('/');
    return '$_davUrl$encoded';
  }

  /// Testa la connessione al server Nextcloud.
  /// Ritorna true se autenticazione e accesso riusciti.
  Future<bool> testConnection() async {
    try {
      final response = await _client
          .send(http.Request('PROPFIND', Uri.parse(_fullUrl('/')))
            ..headers.addAll({
              ..._authHeaders,
              'Depth': '0',
              'Content-Type': 'application/xml',
            }))
          .timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

      _drainStream(response);
      return response.statusCode == 207; // Multi-Status = successo
    } catch (e) {
      return false;
    }
  }

  /// Lista file e cartelle in un path remoto.
  Future<List<WebDavItem>> listDirectory(String remotePath) async {
    try {
      final request = http.Request('PROPFIND', Uri.parse(_fullUrl(remotePath)));
      request.headers.addAll({
        ..._authHeaders,
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      });
      request.body = '''<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getetag/>
    <d:getlastmodified/>
    <d:getcontenttype/>
  </d:prop>
</d:propfind>''';

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

      if (streamedResponse.statusCode == 404) {
        _drainStream(streamedResponse);
        _recordSuccess(); // genuine not-found, not a client health issue
        throw WebDavException('PROPFIND 404', 404);
      }
      if (streamedResponse.statusCode != 207) {
        _drainStream(streamedResponse);
        _recordFailure('listDirectory', 'status ${streamedResponse.statusCode}');
        throw WebDavException(
          'PROPFIND failed: ${streamedResponse.statusCode}',
          streamedResponse.statusCode,
        );
      }

      final body = await streamedResponse.stream.bytesToString();
      _recordSuccess();
      // Large multistatus payloads (a 400-page notebook's pages/ listing
      // is 100-200 KB of XML) take tens of ms to parse — done on the UI
      // isolate that lands mid-stroke and visibly segments the curve
      // being drawn. Hop to a worker isolate past the threshold; small
      // listings stay inline (isolate spawn would cost more than parse).
      if (body.length > _xmlIsolateThreshold) {
        return compute(
          _parseMultiStatusEntry,
          _MultiStatusArgs(body, remotePath, _davUrl),
        );
      }
      return parseMultiStatus(body, remotePath, _davUrl);
    } on WebDavException {
      rethrow;
    } catch (e) {
      _recordFailure('listDirectory', e);
      rethrow;
    }
  }

  /// XML bodies above this size parse on a worker isolate.
  static const int _xmlIsolateThreshold = 32 * 1024;

  /// Scarica un file dal server.
  ///
  /// [timeoutSeconds] overrides the default; pass a larger value for known-
  /// big files (root .ncnote ZIPs in particular).  Default `null` falls
  /// back to the general WebDAV timeout — fine for most page/asset GETs.
  ///
  /// Post-GET integrity check: if the server sends a `Content-Length`
  /// header we compare it against `bodyBytes.length` and reject mismatches.
  /// Observed in the wild: Nextcloud over a Tailscale relay occasionally
  /// returns a partial body (truncated at a 1024- or 65536-byte buffer
  /// boundary) with status 200. `package:http` does NOT raise for that —
  /// it just hands back the short buffer. Without verification the caller
  /// (a delta pull, a JSON parse, a PNG decoder) blows up downstream and
  /// on `metadata.json` the entire pull aborts mid-way, so
  /// `_lastPageEtags` never advances and the next pull cycle restarts
  /// the same 300-page download forever. We retry up to
  /// [_downloadMaxAttempts] times with exponential backoff before
  /// surfacing a [WebDavTruncatedDownloadException].
  ///
  /// When [criticalVerify] is true (used for `metadata.json` /
  /// `document.json`, the two files whose corruption aborts the entire
  /// pull) we additionally PROPFIND the file when the response had no
  /// `Content-Length` header — Nextcloud routinely sends chunked
  /// responses, which means the cheap header check is null even though
  /// the body was silently cut mid-stream. The +1 RTT is well worth it:
  /// without this, a single bad metadata download wedges the notebook
  /// in the 0-of-N pull loop forever.
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds,
      bool criticalVerify = false,
      String? ifNoneMatchEtag}) async {
    Object? lastError;
    for (var attempt = 0; attempt < _downloadMaxAttempts; attempt++) {
      try {
        final headers = ifNoneMatchEtag == null
            ? _authHeaders
            : <String, String>{
                ..._authHeaders,
                'If-None-Match': '"${ifNoneMatchEtag.replaceAll('"', '')}"',
              };
        final response = await _client
            .get(
              Uri.parse(_fullUrl(remotePath)),
              headers: headers,
            )
            .timeout(Duration(
                seconds: timeoutSeconds ?? AppConfig.webdavTimeoutSeconds));

        if (response.statusCode == 304) {
          // Not Modified — caller already has fresh bytes. Signal this
          // distinctly so the caller can keep its cached payload instead
          // of treating the empty body as an error.
          _recordSuccess();
          throw WebDavNotModifiedException(remotePath, ifNoneMatchEtag!);
        }
        if (response.statusCode == 404) {
          _recordSuccess();
          throw WebDavException('GET 404', 404);
        }
        if (response.statusCode != 200) {
          _recordFailure('downloadFile', 'status ${response.statusCode}');
          throw WebDavException(
            'GET failed: ${response.statusCode}',
            response.statusCode,
          );
        }

        final bytes = response.bodyBytes;

        // Empty-body short-circuit. When Tailscale closes the connection
        // before the server's response body is sent (very common on flap),
        // we get a 200 OK with zero bytes. Without this guard:
        //   - Per-PUT verify "trusted the body" → 0-byte was accepted
        //   - Caller jsonDecode("") → FormatException
        //   - Pull aborted, _lastPageEtags never persisted, next tick
        //     restarts a full re-pull from scratch → infinite loop
        // Treat empty 200 as a transient failure and retry.
        if (bytes.isEmpty) {
          _recordFailure('downloadFile', 'empty body ($remotePath)');
          lastError = WebDavTruncatedDownloadException(remotePath, -1, 0);
          if (attempt < _downloadMaxAttempts - 1) {
            await Future.delayed(
                Duration(milliseconds: 400 * (1 << attempt)));
            continue;
          }
          throw lastError as WebDavTruncatedDownloadException;
        }

        // Detect gzipped responses. dart:io decompresses transparently
        // (autoUncompress=true) but does NOT update the Content-Length
        // header — it still reflects the *compressed* wire size, while
        // bodyBytes contains decompressed bytes. Documented explicitly in
        // dart:io HttpClientResponseCompressionState: "Content-Length
        // cannot be trusted [when decompressed]". Comparing them blindly
        // would throw WebDavTruncatedDownloadException on EVERY successful
        // gzipped JSON download. Skip the header check in that case.
        final encoding = (response.headers['content-encoding'] ?? '')
            .toLowerCase();
        final isDecompressed = encoding.contains('gzip') ||
            encoding.contains('deflate') || encoding.contains('br');
        final declared = response.contentLength;
        int? expectedSize =
            (isDecompressed || declared == null) ? null : declared;

        // criticalVerify (metadata.json / document.json): always confirm
        // via PROPFIND. The header check above can't be trusted under
        // gzip and Nextcloud frequently chunks these — without an
        // independent size source a truncated GET sneaks past as a valid
        // (parseable up to the cut) JSON and then strands _lastPageEtags
        // forever. +1 RTT for these two files is a fair price.
        if (criticalVerify) {
          try {
            final propfindSize = await getContentLength(remotePath)
                .timeout(const Duration(seconds: 10));
            if (propfindSize != null) expectedSize = propfindSize;
          } catch (e) {
            // ignore: avoid_print
            print('[WebDAV] downloadFile critical-verify: PROPFIND failed '
                'for $remotePath: $e — trusting body');
          }
        } else if (expectedSize == null &&
            bytes.isNotEmpty &&
            bytes.length % 1024 == 0) {
          // Defense-in-depth for non-criticalVerify paths (assets,
          // pages, symbols): when Content-Length was absent (chunked
          // response — Tailscale relay does this routinely) AND the
          // body is exactly 1024-aligned, that's the historic
          // truncation fingerprint. Same defense the upload path
          // applies: confirm the real size via PROPFIND, let the
          // existing mismatch path drive retry+Range-recovery on
          // truncation. The PROPFIND cost is paid ONLY when we already
          // see a suspicious body — clean downloads pay nothing.
          //
          // Without this, asset bytes truncated at a 1024-aligned cut
          // sneak through and end up in the local .ncnote ZIP cache,
          // causing `ui.instantiateImageCodec` to throw on every page
          // paint until the user re-imports the source PDF.
          try {
            final propfindSize = await getContentLength(remotePath)
                .timeout(const Duration(seconds: 10));
            if (propfindSize != null) expectedSize = propfindSize;
          } catch (e) {
            // ignore: avoid_print
            print('[WebDAV] downloadFile 1024-suspicion: PROPFIND failed '
                'for $remotePath: $e — trusting body');
          }
        }

        if (expectedSize != null && expectedSize != bytes.length) {
          // ignore: avoid_print
          print('[WebDAV] downloadFile TRUNCATED $remotePath: '
              'expected ${expectedSize}B, received ${bytes.length}B '
              '(diff ${expectedSize - bytes.length}B) — retry attempt '
              '${attempt + 1}/$_downloadMaxAttempts');
          _recordFailure('downloadFile',
              'truncated ${bytes.length}/$expectedSize');
          lastError = WebDavTruncatedDownloadException(
              remotePath, expectedSize, bytes.length);
          if (attempt < _downloadMaxAttempts - 1) {
            await Future.delayed(
                Duration(milliseconds: 400 * (1 << attempt)));
            continue;
          }
          // Last-resort: full-GET keeps truncating on this path (observed
          // on Tailscale where every full GET cuts at exactly 32768 B,
          // affecting files whose total size exceeds that boundary). Fall
          // back to Range-based chunked GETs — the server can deliver
          // small chunks even when it can't stream the whole body.
          try {
            final assembled = await _downloadByRange(
                remotePath, expectedSize,
                timeoutSeconds: timeoutSeconds);
            // ignore: avoid_print
            print('[WebDAV] downloadFile RANGE-RECOVERED $remotePath: '
                '${assembled.length}B via chunked Range');
            _recordSuccess();
            return assembled;
          } catch (rangeErr) {
            // ignore: avoid_print
            print('[WebDAV] downloadFile range fallback also failed for '
                '$remotePath: $rangeErr');
            throw lastError as WebDavTruncatedDownloadException;
          }
        }

        _recordSuccess();
        return bytes;
      } on WebDavTruncatedDownloadException {
        rethrow;
      } on WebDavNotModifiedException {
        // 304 is a SUCCESS signal (cache hit), recorded as such above —
        // it must not fall into the transport-error handler below, where
        // it would bump _consecutiveFailures and eventually tear down a
        // perfectly healthy connection pool during routine polling.
        rethrow;
      } on WebDavException catch (e) {
        // 4xx is permanent (missing file, auth): retrying wastes time and
        // callers depend on a prompt 404. Exceptions: 423 Locked (another
        // sync client holds a transient WebDAV lock, clears in seconds)
        // and 429 (rate limit) are retryable. 5xx / unexpected codes are
        // transient (gateway timeout, relay flap): retry with backoff.
        final permanent = e.statusCode >= 400 && e.statusCode < 500 &&
            e.statusCode != 423 && e.statusCode != 429;
        if (permanent || attempt >= _downloadMaxAttempts - 1) rethrow;
        lastError = e;
        await Future.delayed(Duration(milliseconds: 400 * (1 << attempt)));
        continue;
      } catch (e) {
        // Transport-level failure (timeout, socket closed mid-read,
        // ClientException). All transient — retry like uploadFile does.
        // Pre-fix this rethrew immediately, so the attempt loop only
        // ever served empty-body/truncation cases and a single timeout
        // failed the whole page pull.
        _recordFailure('downloadFile', e);
        if (attempt >= _downloadMaxAttempts - 1) rethrow;
        lastError = e;
        await Future.delayed(Duration(milliseconds: 400 * (1 << attempt)));
        continue;
      }
    }
    throw lastError ?? StateError('downloadFile: exhausted attempts');
  }

  static const int _downloadMaxAttempts = 3;

  /// Chunk size for Range-based downloads. Chosen below 32 KB because
  /// that's the observed truncation boundary on Tailscale (a single
  /// GET that asks for more than ~32 KB tends to get cut mid-stream).
  /// 30000 B leaves headroom for any server-side overhead while still
  /// keeping the number of round-trips low (~4 chunks per 120 KB file).
  static const int _rangeChunkSize = 30000;

  /// Fallback download path used when full-GET keeps truncating. Asks
  /// the server for the body in small Range slices (each below the
  /// observed 32 KB cut-point), reassembles them, and returns the
  /// full payload. Throws [WebDavTruncatedDownloadException] if even
  /// the chunked path can't assemble [expectedSize] bytes.
  Future<Uint8List> _downloadByRange(String remotePath, int expectedSize,
      {int? timeoutSeconds}) async {
    // Preallocate the destination buffer: accumulating into a growable
    // List<int> boxes every byte and pays a second full copy in
    // Uint8List.fromList — on a multi-MB recovery that's real memory
    // churn at exactly the moment the link is already struggling.
    final assembled = Uint8List(expectedSize);
    var offset = 0;
    while (offset < expectedSize) {
      final end = (offset + _rangeChunkSize > expectedSize)
          ? expectedSize - 1
          : offset + _rangeChunkSize - 1;
      final headers = <String, String>{
        ..._authHeaders,
        'Range': 'bytes=$offset-$end',
      };
      // Per-chunk retry: a single flaky chunk shouldn't abort the whole
      // recovery. Three attempts with short backoff is enough — if the
      // link is truly down, throwing surfaces it to the caller.
      Uint8List? chunk;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final response = await _client
              .get(Uri.parse(_fullUrl(remotePath)), headers: headers)
              .timeout(Duration(
                  seconds: timeoutSeconds ?? AppConfig.webdavTimeoutSeconds));
          // 206 Partial Content is the well-formed response; some servers
          // answer 200 with the full body when they don't honour Range —
          // treat that as success too as long as bytes match the request.
          if (response.statusCode != 206 && response.statusCode != 200) {
            throw WebDavException(
                'Range GET status ${response.statusCode}',
                response.statusCode);
          }
          final body = response.bodyBytes;
          final wantedLen = end - offset + 1;
          if (response.statusCode == 200) {
            // Server ignored Range and sent everything. Slice client-side.
            if (body.length < expectedSize) {
              throw WebDavException(
                  '200 fallback body truncated: ${body.length}/$expectedSize',
                  200);
            }
            // We already hold the complete body — return it directly
            // instead of re-downloading the full file once per remaining
            // chunk (a non-Range server used to cost
            // ceil(expectedSize/chunkSize) full-body GETs).
            return body.sublist(0, expectedSize);
          } else {
            if (body.length != wantedLen) {
              throw WebDavException(
                  'Range body length mismatch: got ${body.length} '
                  'wanted $wantedLen',
                  206);
            }
            chunk = body;
          }
          break;
        } catch (e) {
          if (attempt == 2) rethrow;
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
      assembled.setRange(offset, end + 1, chunk!);
      offset = end + 1;
    }
    return assembled;
  }

  /// Carica un file sul server. Crea o sovrascrive.
  /// Ritorna l'ETag della nuova versione.
  /// [timeoutSeconds] overrides the default timeout for this call.
  ///
  /// Post-PUT integrity check: after every successful PUT we re-read the
  /// remote `getcontentlength` via PROPFIND and compare it against
  /// `data.length`. This catches the silent-truncation scenario where the
  /// HTTP layer reports 201/204 but the server actually committed a
  /// partial body (observed: large stroke pages frozen at 256 KB or
  /// other 1024-byte aligned offsets after an interrupted iOS background
  /// PUT or a Tailscale stall). On mismatch we retry the upload with
  /// exponential backoff; if every attempt produces a short body we
  /// throw [WebDavSizeMismatchException] so the caller knows the server
  /// state is poisoned and can heal it (or surface the error) — this is
  /// strictly better than silently leaving truncated bytes on the
  /// server, which causes downstream clients to fail forever with
  /// `FormatException` while pulling.
  ///
  /// The verification is skipped only for files small enough that no
  /// real-world HTTP buffer/proxy would truncate them ([_uploadVerifyMin]).
  Future<String?> uploadFile(String remotePath, Uint8List data,
      {int? timeoutSeconds,
       bool criticalVerify = false,
       bool skipVerify = false}) async {
    Object? lastError;
    for (var attempt = 0; attempt < _uploadMaxAttempts; attempt++) {
      try {
        final response = await _client.put(
          Uri.parse(_fullUrl(remotePath)),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/octet-stream',
          },
          body: data,
        ).timeout(Duration(seconds: timeoutSeconds ?? AppConfig.webdavTimeoutSeconds));

        if (response.statusCode != 201 && response.statusCode != 204) {
          _recordFailure('uploadFile', 'status ${response.statusCode}');
          throw WebDavException(
            'PUT failed: ${response.statusCode}',
            response.statusCode,
          );
        }

        // Post-PUT size verification. PROPFIND (not HEAD) so we read the
        // uncompressed on-disk byte count regardless of mod_deflate.
        // criticalVerify lowers the size gate to 0 — used for commit-marker
        // files (document.json, metadata.json) which can be just a few KB
        // but whose corruption breaks the whole notebook for every device.
        // skipVerify suppresses the per-PUT PROPFIND entirely — used by
        // syncDelta when uploading asset batches that get verified via
        // a single directory-level PROPFIND after the parallel uploads
        // (1 RTT vs N).
        final verifyThreshold = criticalVerify ? 0 : _uploadVerifyMin;
        if (!skipVerify && data.length >= verifyThreshold) {
          int? remoteSize;
          // PROPFIND verify with one in-place retry on failure for critical
          // files. Critical here means: keep retrying the *PROPFIND*, NOT
          // the PUT — re-PUTting a successfully-uploaded file just bumps
          // the ETag and triggers spurious pulls on every other device,
          // which on a flaky link spirals into cross-device ping-pong.
          // The PUT already happened; we only need to confirm the body.
          // Always give the verify PROPFIND multiple tries: it's a cheap
          // request, and failing it below re-runs the whole (expensive) PUT.
          const verifyAttempts = 3;
          Object? verifyError;
          for (var v = 0; v < verifyAttempts; v++) {
            try {
              remoteSize = await getContentLength(remotePath)
                  .timeout(const Duration(seconds: 30));
              verifyError = null;
              break;
            } catch (e) {
              verifyError = e;
              if (v < verifyAttempts - 1) {
                await Future.delayed(
                    Duration(milliseconds: 500 * (1 << v)));
              }
            }
          }
          if (verifyError != null) {
            // Could not confirm the server stored the full body. The old
            // code "trusted the PUT" here — but the network conditions
            // that break the verify PROPFIND (relay flap, stall) are
            // exactly the ones that silently truncate PUT bodies, so
            // trusting is how poisoned pages reached the server. Treat
            // the attempt as failed instead: statusCode 0 is non-4xx, so
            // the retry loop below re-PUTs with backoff, and after the
            // final attempt the caller sees the failure and keeps the
            // page dirty (re-PUT is idempotent; worst case is a spurious
            // ETag bump on a healthy server).
            _recordFailure('uploadFile', 'verify unreachable: $verifyError');
            throw WebDavException(
                'verify unreachable for $remotePath: $verifyError', 0);
          }
          if (remoteSize != null && remoteSize != data.length) {
            // ignore: avoid_print
            print('[WebDAV] uploadFile SIZE MISMATCH on $remotePath: '
                'sent ${data.length}B, server has ${remoteSize}B '
                '(diff ${data.length - remoteSize}B) — retry attempt '
                '${attempt + 1}/$_uploadMaxAttempts');
            _recordFailure('uploadFile',
                'size mismatch ${data.length} vs $remoteSize');
            lastError = WebDavSizeMismatchException(
              remotePath, data.length, remoteSize);
            // Backoff before retry: 400ms, 1.2s.
            if (attempt < _uploadMaxAttempts - 1) {
              await Future.delayed(
                  Duration(milliseconds: 400 * (1 << attempt)));
              continue;
            }
            throw lastError as WebDavSizeMismatchException;
          }
        }

        _recordSuccess();
        final headerEtag = response.headers['etag']?.replaceAll('"', '');
        if (headerEtag != null) return headerEtag;
        // Alcuni server non-sabre (wsgidav/Seafile, certi mod_dav) non
        // mandano l'ETag nella risposta al PUT. Recuperalo via PROPFIND:
        // costa un RTT extra ma solo su quei server (Nextcloud/ownCloud
        // lo mandano sempre). Best-effort: un ETag null è già gestito
        // dai chiamanti, un PUT riuscito non deve fallire per questo.
        try {
          return await getEtag(remotePath);
        } catch (_) {
          return null;
        }
      } on WebDavSizeMismatchException {
        // Size-mismatch already drove its own attempt loop above; if we
        // reach here it's the final throw from line 661 (exhausted).
        rethrow;
      } on WebDavException catch (e) {
        // 4xx is permanent (auth, bad request): don't waste attempts.
        // Exceptions: 423 Locked (another sync client holds a transient
        // WebDAV lock — Nextcloud clears it within seconds) and 429 (rate
        // limit) are retryable. 5xx and unexpected codes are transient
        // (server hiccup, gateway timeout, Tailscale relay flap): retry
        // with backoff, matching the comment-promised "exponential backoff
        // up to _uploadMaxAttempts". Pre-fix, every uploadFile failure
        // short-circuited the loop and made one save() = one PUT attempt.
        final permanent = e.statusCode >= 400 && e.statusCode < 500 &&
            e.statusCode != 423 && e.statusCode != 429;
        if (permanent || attempt >= _uploadMaxAttempts - 1) rethrow;
        lastError = e;
        await Future.delayed(Duration(milliseconds: 400 * (1 << attempt)));
        continue;
      } catch (e) {
        // Transport-level failure (timeout, socket closed, ClientException,
        // FormatException from a half-baked response). All transient by
        // nature — retry until we run out of attempts.
        _recordFailure('uploadFile', e);
        if (attempt >= _uploadMaxAttempts - 1) rethrow;
        lastError = e;
        await Future.delayed(Duration(milliseconds: 400 * (1 << attempt)));
        continue;
      }
    }
    // Unreachable: loop either returns or throws.
    throw lastError ?? StateError('uploadFile: exhausted attempts');
  }

  /// Skip post-PUT verification under this size — too small to truncate
  /// in any realistic HTTP/proxy chain, and the PROPFIND round-trip would
  /// double the cost of metadata.json/document.json commits which fire on
  /// every save.
  static const int _uploadVerifyMin = 64 * 1024;
  static const int _uploadMaxAttempts = 3;

  /// Crea una cartella remota.
  Future<void> createDirectory(String remotePath) async {
    final request = http.Request('MKCOL', Uri.parse(_fullUrl(remotePath)));
    request.headers.addAll(_authHeaders);

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

    _drainStream(response);
    if (response.statusCode != 201 && response.statusCode != 405) {
      // 405 = già esiste, OK
      throw WebDavException(
        'MKCOL failed: ${response.statusCode}',
        response.statusCode,
      );
    }
  }

  /// Elimina un file o cartella remota.
  Future<void> delete(String remotePath) async {
    final response = await _client.delete(
      Uri.parse(_fullUrl(remotePath)),
      headers: _authHeaders,
    ).timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

    if (response.statusCode != 204 && response.statusCode != 404) {
      throw WebDavException(
        'DELETE failed: ${response.statusCode}',
        response.statusCode,
      );
    }
  }

  /// Muove/rinomina un file o cartella remota.
  Future<void> move(String fromPath, String toPath) async {
    final request = http.Request('MOVE', Uri.parse(_fullUrl(fromPath)));
    request.headers.addAll({
      ..._authHeaders,
      'Destination': _fullUrl(toPath),
      'Overwrite': 'F',
    });

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

    _drainStream(response);
    if (response.statusCode != 201 && response.statusCode != 204) {
      throw WebDavException(
        'MOVE failed: ${response.statusCode}',
        response.statusCode,
      );
    }
  }

  /// Ottieni ETag + Last-Modified di un file remoto in una sola PROPFIND.
  /// Usato dal sync per decidere chi vince in caso di conflitto (remote vs local).
  Future<({String? etag, DateTime? lastModified})?> getFileInfo(
      String remotePath) async {
    try {
      final request = http.Request('PROPFIND', Uri.parse(_fullUrl(remotePath)));
      request.headers.addAll({
        ..._authHeaders,
        'Depth': '0',
        'Content-Type': 'application/xml; charset=utf-8',
      });
      request.body = '''<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getetag/>
    <d:getlastmodified/>
  </d:prop>
</d:propfind>''';

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

      if (streamedResponse.statusCode != 207) {
        _drainStream(streamedResponse);
        return null;
      }

      final body = await streamedResponse.stream.bytesToString();
      final document = XmlDocument.parse(body);
      String? etag;
      final etagEls = document.findAllElements('getetag', namespace: '*');
      if (etagEls.isNotEmpty) {
        etag = etagEls.first.innerText.replaceAll('"', '');
      }
      DateTime? lastModified;
      final lmEls = document.findAllElements('getlastmodified', namespace: '*');
      if (lmEls.isNotEmpty && lmEls.first.innerText.isNotEmpty) {
        lastModified = _parseHttpDate(lmEls.first.innerText);
      }
      return (etag: etag, lastModified: lastModified);
    } catch (_) {
      return null;
    }
  }

  /// Ottieni l'ETag di un file remoto (per conflict detection).
  Future<String?> getEtag(String remotePath) async {
    try {
      final request = http.Request('PROPFIND', Uri.parse(_fullUrl(remotePath)));
      request.headers.addAll({
        ..._authHeaders,
        'Depth': '0',
        'Content-Type': 'application/xml; charset=utf-8',
      });
      request.body = '''<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getetag/>
  </d:prop>
</d:propfind>''';

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

      if (streamedResponse.statusCode == 404) {
        // A genuine 404 is NOT a client-health failure — the file just
        // doesn't exist. Let callers distinguish via the thrown exception.
        _drainStream(streamedResponse);
        _recordSuccess();
        throw WebDavException('PROPFIND 404', 404);
      }
      if (streamedResponse.statusCode != 207) {
        _drainStream(streamedResponse);
        // Throw (don't return null): callers like deltaFolderExists treat a
        // completed call as "file exists". Returning null on a transient
        // 5xx/423/507 made a never-uploaded notebook look already-synced,
        // clearing its dirty flag forever (silent data loss).
        _recordFailure('getEtag', 'status ${streamedResponse.statusCode}');
        throw WebDavException(
            'PROPFIND status ${streamedResponse.statusCode}',
            streamedResponse.statusCode);
      }

      final body = await streamedResponse.stream.bytesToString();
      final document = XmlDocument.parse(body);
      final etagElements = document.findAllElements('getetag', namespace: '*');
      if (etagElements.isEmpty) {
        _recordFailure('getEtag', 'empty response body');
        return null;
      }
      _recordSuccess();
      return etagElements.first.innerText.replaceAll('"', '');
    } on WebDavException {
      rethrow;
    } catch (e) {
      _recordFailure('getEtag', e);
      // Rethrow so callers (e.g. deltaFolderExists) can distinguish
      // 'network uncertainty' from 'definite 404'. The older 'return
      // null on any error' swallowed network issues and caused the
      // library to wipe local notebooks during Tailscale blips.
      rethrow;
    }
  }

  /// Assicura che la cartella base dell'app esista sul server.
  Future<void> ensureBaseDirectory() async {
    await createDirectory(basePath);
  }

  /// Ottieni la dimensione di un file remoto (Content-Length).
  /// Returns null if the file doesn't exist or size can't be determined.
  Future<int?> getContentLength(String remotePath) async {
    final request = http.Request('PROPFIND', Uri.parse(_fullUrl(remotePath)));
    request.headers.addAll({
      ..._authHeaders,
      'Depth': '0',
      'Content-Type': 'application/xml; charset=utf-8',
    });
    request.body = '''<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getcontentlength/>
  </d:prop>
</d:propfind>''';

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: AppConfig.webdavTimeoutSeconds));

    if (streamedResponse.statusCode != 207) {
      _drainStream(streamedResponse);
      return null;
    }

    final body = await streamedResponse.stream.bytesToString();
    final document = XmlDocument.parse(body);
    final clElements = document.findAllElements('getcontentlength', namespace: '*');
    if (clElements.isEmpty || clElements.first.innerText.isEmpty) return null;
    return int.tryParse(clElements.first.innerText);
  }

  /// True dopo il primo HEAD 200 senza header ETag: il server non espone
  /// l'ETag su HEAD (wsgidav/Seafile, certi mod_dav). Da lì in poi
  /// [getEtagFast] ritorna subito null e il chiamante va dritto al
  /// PROPFIND, senza pagare un HEAD destinato a fallire a ogni check —
  /// e senza che quei "fallimenti" alimentino il detector zombie-client
  /// facendo ricostruire il pool di continuo.
  bool _headEtagUnsupported = false;

  /// Fast ETag check via HEAD — single request, no XML parse.
  /// Falls back to null on any error (caller retries via PROPFIND).
  /// Feeds the zombie-client detector: repeated nulls rebuild the client.
  Future<String?> getEtagFast(String remotePath) async {
    if (_headEtagUnsupported) return null;
    try {
      final response = await _client.head(
        Uri.parse(_fullUrl(remotePath)),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        // Genuine not-found (e.g. a never-pushed notebook's metadata.json)
        // is NOT a client-health failure — mirroring getEtag/listDirectory.
        // Counting it fed the zombie detector and produced a spurious
        // "Recovered" log on the very next successful call, every poll.
        _recordSuccess();
        return null;
      }
      if (response.statusCode != 200) {
        _recordFailure('getEtagFast', 'status ${response.statusCode}');
        return null;
      }
      final etag = response.headers['etag'];
      if (etag == null) {
        if (response.headers.isNotEmpty) {
          // 200 con header veri ma senza ETag: il server semplicemente
          // non manda ETag su HEAD. Non è un problema di salute del
          // client — ricordalo e salta HEAD d'ora in poi.
          _headEtagUnsupported = true;
          return null;
        }
        // HEAD succeeded status-wise but response missing headers is the
        // classic 'zombie client' symptom on iOS NSURLSession.
        _recordFailure('getEtagFast', 'missing etag header');
        return null;
      }
      _recordSuccess();
      return etag.replaceAll('"', '');
    } catch (e) {
      _recordFailure('getEtagFast', e);
      return null;
    }
  }

  /// Parsa la risposta XML Multi-Status di PROPFIND.
  ///
  /// Robusto contro risposte malformate (server buggati, proxy che alterano
  /// il namespace, propstat con status != 200): ogni entry che non espone i
  /// campi attesi viene semplicemente saltata invece di far esplodere
  /// l'intera listing con un NoSuchElementError.
  ///
  /// Static (davUrl passed in) so [compute] can run it on a worker
  /// isolate for large listings — see [listDirectory].
  ///
  /// Il matching degli elementi è namespace-aware (local name, qualsiasi
  /// prefisso): sabre/Nextcloud usano `d:`, Apache mod_dav e wsgidav/Seafile
  /// usano `D:` o il namespace di default — il vecchio matching sul
  /// qualified name `d:...` restituiva listing vuoti su quei server.
  @visibleForTesting
  static List<WebDavItem> parseMultiStatus(
      String xml, String requestPath, String davUrl) {
    final document = XmlDocument.parse(xml);
    final responses = document.findAllElements('response', namespace: '*');
    final items = <WebDavItem>[];

    for (final response in responses) {
      try {
        final hrefEls = response.findElements('href', namespace: '*');
        if (hrefEls.isEmpty) continue;
        final href = hrefEls.first.innerText;
        final decodedHref = Uri.decodeFull(href);

        // Salta l'entry della directory stessa
        final normalizedRequest = requestPath.endsWith('/')
            ? requestPath
            : '$requestPath/';
        if (decodedHref.endsWith(normalizedRequest) ||
            decodedHref == davUrl + normalizedRequest) {
          continue;
        }

        // Preferisci il propstat con status 200 (alcuni server restituiscono
        // più propstat: uno con i successi, uno con le prop not-found).
        final propstats = response.findElements('propstat', namespace: '*').toList();
        if (propstats.isEmpty) continue;
        XmlElement? propstat;
        for (final ps in propstats) {
          final statusEls = ps.findElements('status', namespace: '*');
          if (statusEls.isEmpty) continue;
          if (statusEls.first.innerText.contains('200')) {
            propstat = ps;
            break;
          }
        }
        propstat ??= propstats.first;

        final propEls = propstat.findElements('prop', namespace: '*');
        if (propEls.isEmpty) continue;
        final prop = propEls.first;

        final rtEls = prop.findElements('resourcetype', namespace: '*');
        final isDir = rtEls.isNotEmpty &&
            rtEls.first.findElements('collection', namespace: '*').isNotEmpty;

        final segments =
            decodedHref.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty) continue;
        // decodedHref è GIÀ decodato: un secondo decode corrompeva i nomi
        // contenenti `%XX` letterali (es. `50%20.pdf` → `50 .pdf`) e, se il
        // `%` non era seguito da hex, lanciava e l'entry veniva scartata
        // dalla listing (asset esistente invisibile al diff del pull).
        final name = segments.last;

        String? etag;
        final etagEl = prop.findElements('getetag', namespace: '*');
        if (etagEl.isNotEmpty) {
          etag = etagEl.first.innerText.replaceAll('"', '');
        }

        int? contentLength;
        final clEl = prop.findElements('getcontentlength', namespace: '*');
        if (clEl.isNotEmpty && clEl.first.innerText.isNotEmpty) {
          contentLength = int.tryParse(clEl.first.innerText);
        }

        DateTime? lastModified;
        final lmEl = prop.findElements('getlastmodified', namespace: '*');
        if (lmEl.isNotEmpty && lmEl.first.innerText.isNotEmpty) {
          lastModified = _parseHttpDate(lmEl.first.innerText);
        }

        String? contentType;
        final ctEl = prop.findElements('getcontenttype', namespace: '*');
        if (ctEl.isNotEmpty) {
          contentType = ctEl.first.innerText;
        }

        items.add(WebDavItem(
          path: decodedHref,
          name: name,
          isDirectory: isDir,
          contentLength: contentLength,
          etag: etag,
          lastModified: lastModified,
          contentType: contentType,
        ));
      } catch (e) {
        // Singola entry malformata non deve invalidare tutta la listing.
        // ignore: avoid_print
        print('[WebDAV] Skipping malformed PROPFIND entry: $e');
      }
    }

    return items;
  }

  /// Chiude il client HTTP.
  void dispose() {
    _client.close();
  }
}

/// Args for [_parseMultiStatusEntry] — must be a plain sendable object.
class _MultiStatusArgs {
  final String xml;
  final String requestPath;
  final String davUrl;
  const _MultiStatusArgs(this.xml, this.requestPath, this.davUrl);
}

/// Top-level [compute] entry point for off-thread multistatus parsing.
List<WebDavItem> _parseMultiStatusEntry(_MultiStatusArgs a) =>
    WebDavService.parseMultiStatus(a.xml, a.requestPath, a.davUrl);

/// Eccezione specifica per errori WebDAV.
class WebDavException implements Exception {
  final String message;
  final int statusCode;

  WebDavException(this.message, this.statusCode);

  @override
  String toString() => 'WebDavException($statusCode): $message';
}

/// Thrown when a PUT appears to succeed (201/204) but a follow-up
/// PROPFIND shows the server stored a body whose size does not match
/// what we sent. Indicates a silent truncation somewhere in the HTTP
/// chain (proxy buffer, NSURLSession suspension, Tailscale stall) that
/// the PUT response did not surface as an error. Callers should treat
/// the remote file as poisoned and either retry or escalate.
class WebDavSizeMismatchException implements Exception {
  final String remotePath;
  final int sentBytes;
  final int storedBytes;

  WebDavSizeMismatchException(this.remotePath, this.sentBytes, this.storedBytes);

  @override
  String toString() =>
      'WebDavSizeMismatchException($remotePath): sent ${sentBytes}B but '
      'server stored ${storedBytes}B';
}

/// Thrown when a GET returns 200 with a Content-Length header that
/// disagrees with the number of body bytes actually received. Indicates
/// a silent mid-stream cut by some hop in the chain (proxy, Tailscale
/// relay, NSURLSession suspension) that `package:http` does not flag.
/// Treat the bytes as garbage — never feed them to a JSON/image/zip
/// decoder.
class WebDavTruncatedDownloadException implements Exception {
  final String remotePath;
  final int declaredBytes;
  final int receivedBytes;

  WebDavTruncatedDownloadException(
      this.remotePath, this.declaredBytes, this.receivedBytes);

  @override
  String toString() =>
      'WebDavTruncatedDownloadException($remotePath): server declared '
      '${declaredBytes}B but only ${receivedBytes}B were received';
}

/// Raised by [WebDavService.downloadFile] when an `If-None-Match`
/// conditional GET returned 304 Not Modified. The caller's cached
/// bytes are still authoritative; reusing them is the whole point of
/// the conditional GET.
class WebDavNotModifiedException implements Exception {
  final String remotePath;
  final String etag;

  WebDavNotModifiedException(this.remotePath, this.etag);

  @override
  String toString() =>
      'WebDavNotModifiedException($remotePath): server returned 304 '
      'for If-None-Match=$etag';
}

/// Parsa date HTTP (RFC 1123: "Sun, 06 Nov 1994 08:49:37 GMT").
DateTime _parseHttpDate(String dateStr) {
  const months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
  try {
    // Prova ISO 8601 prima
    return DateTime.parse(dateStr);
  } catch (_) {
    // Prova RFC 1123
    final parts = dateStr.split(' ');
    if (parts.length >= 5) {
      final day = int.tryParse(parts[1]) ?? 1;
      final month = months[parts[2]] ?? 1;
      final year = int.tryParse(parts[3]) ?? 2026;
      final timeParts = parts[4].split(':');
      return DateTime.utc(
        year, month, day,
        int.tryParse(timeParts[0]) ?? 0,
        int.tryParse(timeParts[1]) ?? 0,
        timeParts.length > 2 ? (int.tryParse(timeParts[2]) ?? 0) : 0,
      );
    }
    return DateTime.now();
  }
}
