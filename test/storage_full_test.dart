// Running out of space is the one sync failure the user can fix, and the one
// that never fixes itself by waiting. It has to be told apart from a network
// hiccup — retrying it is pointless — and it has to be said out loud.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:abelnotes/core/services/google_drive_store.dart';
import 'package:abelnotes/core/services/remote_store.dart';

class _FixedAuth implements DriveAuth {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'token';
}

void main() {
  test('a full Drive is its own failure, and is not retried', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      // Folder lookup, then the file lookup, then the upload is refused.
      if (calls == 1) {
        return http.Response(jsonEncode({'files': [{'id': 'folder-1'}]}), 200);
      }
      if (calls == 2) return http.Response(jsonEncode({'files': []}), 200);
      return http.Response(
          jsonEncode({
            'error': {
              'errors': [{'reason': 'storageQuotaExceeded'}],
              'message': "The user's Drive storage quota has been exceeded.",
            }
          }),
          403);
    });

    await expectLater(
      GoogleDriveStore(_FixedAuth(), client: client)
          .uploadFile('/AbelNotes/nb.abelnote', Uint8List.fromList([1])),
      throwsA(isA<RemoteStorageFullException>()),
    );
    expect(calls, 3,
        reason: 'retrying costs the user seconds for the same answer');
  });

  test('a rate limit is still retried, unlike a full disk', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) {
        return http.Response(jsonEncode({'files': [{'id': 'folder-1'}]}), 200);
      }
      if (calls == 2) return http.Response(jsonEncode({'files': []}), 200);
      if (calls == 3) {
        return http.Response(
            jsonEncode({
              'error': {
                'errors': [{'reason': 'userRateLimitExceeded'}],
              }
            }),
            403);
      }
      return http.Response(jsonEncode({'id': 'f1', 'md5Checksum': 'v1'}), 200);
    });

    expect(
        await GoogleDriveStore(_FixedAuth(), client: client)
            .uploadFile('/AbelNotes/nb.abelnote', Uint8List.fromList([1])),
        'v1');
  });

  test('storage-full is a RemoteStoreException, so old handlers still catch it',
      () {
    // Callers that only know the general type must not start crashing.
    expect(RemoteStorageFullException('full'), isA<RemoteStoreException>());
    expect(RemoteStorageFullException('full').statusCode, 507);
  });
}
