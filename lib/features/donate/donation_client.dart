// HTTP side of donations: contribute.abelnotes.app (donate/ in the site repo).

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Overridable for a local `wrangler dev` with --dart-define=ABEL_DONATE_URL=.
const String kDonateBaseUrl =
    String.fromEnvironment('ABEL_DONATE_URL', defaultValue: 'https://contribute.abelnotes.app');

/// Consent text version the receiver knows (schema.js CONSENT_VERSIONS).
const String kDonationConsentVersion = '2026-11';

/// Why a request failed. The UI shows a message per case.
enum DonationError { offline, busy, fullToday, refused, notFound, server }

class DonationException implements Exception {
  DonationException(this.error, this.detail);
  final DonationError error;
  final String detail;

  @override
  String toString() => 'DonationException(${error.name}): $detail';
}

class DonationStatus {
  const DonationStatus(this.status, this.samples, this.acceptedSamples);

  /// in_review, accepted or rejected.
  final String status;
  final int samples;
  final int acceptedSamples;
}

class DonationClient {
  DonationClient({http.Client? client, String baseUrl = kDonateBaseUrl})
      : _http = client ?? http.Client(),
        _base = baseUrl;

  final http.Client _http;
  final String _base;
  static const _timeout = Duration(seconds: 30);

  /// Sends one donation body; returns its receipt code.
  Future<String> send(Map<String, Object> body) async {
    final res = await _call(() => _http.post(Uri.parse('$_base/v1/donations'),
        headers: {'content-type': 'application/json'}, body: jsonEncode(body)));
    final receipt = _json(res)['receipt'];
    if (res.statusCode != 201 || receipt is! String) throw _fail(res);
    return receipt;
  }

  Future<DonationStatus> status(String receipt) async {
    final res = await _call(() => _http.get(Uri.parse('$_base/v1/donations/${Uri.encodeComponent(receipt)}')));
    if (res.statusCode != 200) throw _fail(res);
    final j = _json(res);
    return DonationStatus(
        '${j['status']}', (j['samples'] as num?)?.toInt() ?? 0, (j['acceptedSamples'] as num?)?.toInt() ?? 0);
  }

  /// Deletes a donation; one already gone counts as deleted.
  Future<void> delete(String receipt) async {
    final res = await _call(() => _http.delete(Uri.parse('$_base/v1/donations/${Uri.encodeComponent(receipt)}')));
    if (res.statusCode != 204 && res.statusCode != 404) throw _fail(res);
  }

  Future<http.Response> _call(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } catch (e) {
      throw DonationException(DonationError.offline, '$e');
    }
  }

  static Map<String, Object?> _json(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      return j is Map<String, Object?> ? j : const {};
    } catch (_) {
      return const {};
    }
  }

  static DonationException _fail(http.Response res) {
    final code = '${_json(res)['error'] ?? 'http ${res.statusCode}'}';
    return DonationException(
        switch (res.statusCode) {
          429 => DonationError.busy,
          503 when code == 'full_today' => DonationError.fullToday,
          404 => DonationError.notFound,
          >= 400 && < 500 => DonationError.refused,
          _ => DonationError.server,
        },
        code);
  }
}
