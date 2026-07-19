import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/webdav_service.dart';

/// Creates a public share link for a notebook by uploading a rendered PDF to
/// the user's own Nextcloud and asking Nextcloud's OCS Share API for a link.
///
/// Why this shape: sharing reuses the WebDAV/Nextcloud backend the user is
/// already syncing to — no server of ours, no new hosting. The shared PDF is
/// view-only and universal (any browser opens it, recipient needs nothing).
/// It is an explicit per-notebook action, not automatic sync: the note only
/// leaves the device when the user taps share.
///
/// The link points at a PDF under `/AbelNotes/shared/`; the user can revoke
/// it any time from their Nextcloud web UI (Nextcloud owns retention/expiry).
/// A public share: its OCS id (needed to revoke) and public URL.
class ShareLink {
  final String id;
  final String url;
  const ShareLink({required this.id, required this.url});
}

class NextcloudShareService {
  final String serverUrl;
  final String username;
  final String password;

  /// Reused for the PDF upload (handles auth, path-encoding, self-signed
  /// certs and size-verify). The OCS call below is done here directly since
  /// it hits a different API path than WebDAV.
  final WebDavService webdav;

  NextcloudShareService({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.webdav,
  });

  static const String _shareDir = '${AppConfig.defaultRemotePath}shared/';

  String get _serverRoot => serverUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _basicAuth {
    final creds = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $creds'};
  }

  /// Mirrors WebDavService's self-signed-cert tolerance so a homelab
  /// Nextcloud behind a private CA still works for the OCS call.
  http.Client _newClient() {
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return http_io.IOClient(inner);
  }

  /// Remote path a notebook's shared PDF lives at (deterministic from title).
  String remotePathFor(String safeName) => '$_shareDir$safeName.pdf';

  /// The existing public link for this notebook's shared PDF, or null if it
  /// was never shared (or the link was revoked). A cheap GET — no upload — so
  /// the UI can show "already shared" instantly instead of re-doing the whole
  /// upload+create flow every time the user reopens the share sheet.
  Future<ShareLink?> existingLink(String safeName) async {
    final links = await listPublicLinks(remotePathFor(safeName));
    return links.isEmpty ? null : links.first;
  }

  /// Uploads [pdfBytes] as `<safeName>.pdf` under the shared folder and
  /// returns its public share. Reuses an existing public link for that path
  /// instead of creating a duplicate (re-upload refreshes the PDF content in
  /// place). Throws on failure (caller shows the error).
  Future<ShareLink> sharePdf({
    required String safeName,
    required Uint8List pdfBytes,
  }) async {
    // MKCOL is non-recursive — ensure both levels exist. Both no-op (405) if
    // already present.
    await webdav.createDirectory(AppConfig.defaultRemotePath);
    await webdav.createDirectory(_shareDir);

    final remotePath = remotePathFor(safeName);
    await webdav.uploadFile(remotePath, pdfBytes);

    final existing = await listPublicLinks(remotePath);
    if (existing.isNotEmpty) return existing.first;
    return _createPublicLink(remotePath);
  }

  /// Public links (shareType 3) currently on [remotePath], newest first-ish
  /// as OCS returns them. Empty if none. Lets the UI show "already shared →
  /// revoke" instead of piling up duplicate links.
  Future<List<ShareLink>> listPublicLinks(String remotePath) async {
    final uri = Uri.parse('$_serverRoot/ocs/v2.php/apps/files_sharing/api/v1'
        '/shares?format=json&path=${Uri.encodeQueryComponent(remotePath)}');
    final client = _newClient();
    try {
      final resp = await client.get(uri, headers: {
        ..._basicAuth,
        'OCS-APIRequest': 'true',
      });
      if (resp.statusCode != 200) return const [];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = (json['ocs'] as Map?)?['data'];
      if (data is! List) return const [];
      final out = <ShareLink>[];
      for (final item in data) {
        final m = (item as Map?)?.cast<String, dynamic>();
        if (m == null) continue;
        // shareType comes back as int; 3 = public link.
        final type = (m['share_type'] as num?)?.toInt();
        if (type != 3) continue;
        final id = m['id']?.toString();
        final url = m['url'] as String?;
        if (id != null && url != null && url.isNotEmpty) {
          out.add(ShareLink(id: id, url: url));
        }
      }
      return out;
    } catch (_) {
      return const [];
    } finally {
      client.close();
    }
  }

  /// Revokes (deletes) a public share by its OCS id. Throws on failure.
  Future<void> revokeShare(String shareId) async {
    final uri = Uri.parse(
        '$_serverRoot/ocs/v2.php/apps/files_sharing/api/v1/shares/$shareId?format=json');
    final client = _newClient();
    try {
      final resp = await client.delete(uri, headers: {
        ..._basicAuth,
        'OCS-APIRequest': 'true',
      });
      if (resp.statusCode != 200) {
        throw Exception('OCS ${resp.statusCode}: ${resp.body}');
      }
    } finally {
      client.close();
    }
  }

  /// POSTs to the OCS Share API to make [remotePath] a public read-only link.
  /// [remotePath] is relative to the user's files root (same string PUT to
  /// over WebDAV), which is exactly what OCS's `path` expects.
  Future<ShareLink> _createPublicLink(String remotePath) async {
    final uri = Uri.parse(
        '$_serverRoot/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json');
    final client = _newClient();
    try {
      final resp = await client.post(
        uri,
        headers: {
          ..._basicAuth,
          'OCS-APIRequest': 'true',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'path': remotePath,
          'shareType': '3', // public link
          'permissions': '1', // read-only
        },
      );
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw Exception('OCS ${resp.statusCode}: ${resp.body}');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = (json['ocs'] as Map?)?['data'] as Map?;
      final url = data?['url'] as String?;
      final id = data?['id']?.toString();
      if (url == null || url.isEmpty || id == null) {
        throw Exception('OCS response had no share id/url');
      }
      return ShareLink(id: id, url: url);
    } finally {
      client.close();
    }
  }
}
