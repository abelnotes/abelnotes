// Spike: does a `drive.file` grant belong to the Cloud PROJECT or to the
// individual OAuth client ID?
//
// It decides the whole Drive-sync design. With drive.file an app only sees
// files it created. AbelNotes ships one OAuth client per platform (Android,
// desktop, …), so if the grant were per client ID, a notebook created on the
// desktop would be invisible to the phone — i.e. no sync at all.
//
// Google's docs never state it outright. The strongest hint is the Picker's
// setAppId, which takes "The Cloud project number" and is "required for the
// https://www.googleapis.com/auth/drive.file scope" — that reads as
// project-level identity. This script settles it by experiment instead.
//
// HOW TO RUN
//   1. In the same Cloud project create TWO OAuth clients of type
//      "Desktop app" (call them spike-A and spike-B). Two desktop clients,
//      because an Android client is bound to a package name + SHA-1 and
//      cannot be driven from a terminal — the question under test is
//      client-ID-vs-project, and two clients of any type answer it.
//   2. Create a file with A:
//        dart run tool/gdrive_scope_spike.dart create \
//          --id <A_CLIENT_ID> --secret <A_SECRET>
//      It prints a fileId.
//   3. Try to read that file with B:
//        dart run tool/gdrive_scope_spike.dart read <fileId> \
//          --id <B_CLIENT_ID> --secret <B_SECRET>
//
//   200 + the file's metadata -> the grant is per PROJECT. Design holds.
//   404 (Drive hides what you may not see) -> per CLIENT ID. Design breaks,
//   and the fallback is a single client ID shared across platforms or a
//   different scope — decide before writing any sync code.
//
// Sign in with the SAME Google account both times, and make sure that
// account is listed under Test users while the app is in Testing.
//
// The client secret of an installed app is not really secret (anyone can
// extract it from the binary), which is why this uses PKCE and why the
// values are passed on the command line rather than committed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

const _scope = 'https://www.googleapis.com/auth/drive.file';
const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

Future<void> main(List<String> argv) async {
  final args = _Args.parse(argv);
  if (args == null) {
    stderr.writeln('usage: dart run tool/gdrive_scope_spike.dart '
        '<create|read <fileId>> --id <clientId> --secret <clientSecret>');
    exit(64);
  }

  final token = await _authorize(args.clientId, args.clientSecret);

  switch (args.command) {
    case 'create':
      final id = await _createFile(token);
      stdout.writeln('\nCreated fileId: $id');
      stdout.writeln('Now re-run with the OTHER client:');
      stdout.writeln('  dart run tool/gdrive_scope_spike.dart read $id '
          '--id <B_CLIENT_ID> --secret <B_SECRET>');
      break;
    case 'read':
      final res = await _readFile(token, args.fileId!);
      stdout.writeln('\nHTTP ${res.statusCode}');
      stdout.writeln(res.body);
      stdout.writeln(res.statusCode == 200
          ? '\n=> VISIBLE to the other client: the drive.file grant is '
              'per PROJECT. Multi-platform sync works.'
          : '\n=> NOT visible (404 = Drive hides what this client may not '
              'see): the grant is per CLIENT ID. The per-platform-client '
              'design does NOT work as drawn.');
      break;
  }
}

/// Loopback + PKCE authorization code flow for an installed app.
Future<String> _authorize(String clientId, String clientSecret) async {
  final verifier = _randomUrlSafe(64);
  final challenge = base64Url
      .encode(await _sha256(verifier))
      .replaceAll('=', ''); // Google rejects padding

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final redirectUri = 'http://127.0.0.1:${server.port}';

  final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': _scope,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
    // Forces the consent screen so the grant is unambiguous for the test.
    'prompt': 'consent',
    'access_type': 'offline',
  });

  stdout.writeln('Open this URL and sign in:\n\n$authUrl\n');
  final code = await _waitForCode(server);

  final res = await http.post(Uri.parse(_tokenEndpoint), body: {
    'client_id': clientId,
    'client_secret': clientSecret,
    'code': code,
    'code_verifier': verifier,
    'grant_type': 'authorization_code',
    'redirect_uri': redirectUri,
  });
  if (res.statusCode != 200) {
    stderr.writeln('token exchange failed: ${res.statusCode} ${res.body}');
    exit(1);
  }
  return (jsonDecode(res.body) as Map<String, dynamic>)['access_token']
      as String;
}

Future<String> _waitForCode(HttpServer server) async {
  await for (final req in server) {
    final code = req.uri.queryParameters['code'];
    final error = req.uri.queryParameters['error'];
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(code != null
          ? '<h3>Done. Back to the terminal.</h3>'
          : '<h3>Failed: $error</h3>');
    await req.response.close();
    await server.close();
    if (code == null) {
      stderr.writeln('authorization failed: $error');
      exit(1);
    }
    return code;
  }
  throw StateError('server closed before the redirect arrived');
}

Future<String> _createFile(String token) async {
  final res = await http.post(
    Uri.parse('https://www.googleapis.com/drive/v3/files'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'name': 'abelnotes-scope-spike.txt',
      'mimeType': 'text/plain',
    }),
  );
  if (res.statusCode != 200) {
    stderr.writeln('create failed: ${res.statusCode} ${res.body}');
    exit(1);
  }
  return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
}

Future<http.Response> _readFile(String token, String fileId) => http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'
          '?fields=id,name,owners,capabilities'),
      headers: {'Authorization': 'Bearer $token'},
    );

String _randomUrlSafe(int bytes) {
  final r = Random.secure();
  return base64Url
      .encode(List<int>.generate(bytes, (_) => r.nextInt(256)))
      .replaceAll('=', '');
}

/// SHA-256 without pulling in `crypto`: shells out to the platform digest.
Future<List<int>> _sha256(String input) async {
  final proc = await Process.start('openssl', ['dgst', '-sha256', '-binary']);
  proc.stdin.add(utf8.encode(input));
  await proc.stdin.close();
  return proc.stdout.expand((chunk) => chunk).toList();
}

class _Args {
  final String command;
  final String? fileId;
  final String clientId;
  final String clientSecret;
  _Args(this.command, this.fileId, this.clientId, this.clientSecret);

  static _Args? parse(List<String> argv) {
    if (argv.isEmpty) return null;
    final command = argv.first;
    if (command != 'create' && command != 'read') return null;
    String? fileId;
    var i = 1;
    if (command == 'read') {
      if (argv.length < 2) return null;
      fileId = argv[1];
      i = 2;
    }
    String? id, secret;
    for (; i < argv.length - 1; i++) {
      if (argv[i] == '--id') id = argv[i + 1];
      if (argv[i] == '--secret') secret = argv[i + 1];
    }
    if (id == null || secret == null) return null;
    return _Args(command, fileId, id, secret);
  }
}
