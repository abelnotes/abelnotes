import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/config/app_config.dart';

/// The version shown in Settings → About and stamped on every crash log is a
/// hand-maintained constant, because Flutter's generated version.json does not
/// exist on Windows or Linux. These tests are what keeps it honest.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('app version', () {
    test('matches the version: line in pubspec.yaml', () {
      final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
              multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull, reason: 'no parsable version: line in pubspec.yaml');

      expect(AppConfig.appVersion, m!.group(1),
          reason: 'bump AppConfig.appVersion to match pubspec');
      expect(AppConfig.appBuildNumber, int.parse(m.group(2)!),
          reason: 'bump AppConfig.appBuildNumber to match pubspec');
    });

    test('msix_version is four numbers ending in 0', () {
      // Deliberately NOT tied to appVersion: msix_version only has to increase
      // on every submission, which a resubmission with no code change does on
      // its own. The fourth number must stay 0 — Microsoft reserves it.
      final m = RegExp(r'^\s*msix_version:\s*\d+\.\d+\.\d+\.(\d+)\s*$',
              multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull, reason: 'no parsable msix_version in pubspec.yaml');
      expect(m!.group(1), '0', reason: 'the fourth number is reserved');
    });
  });
}
