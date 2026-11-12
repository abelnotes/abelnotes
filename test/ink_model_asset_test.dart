// The bundled formula model: listed by name with its notice, and pinned by hash
// so other weights (other data, other licence) never ship by accident.
import 'dart:io';

import 'package:abelnotes/features/canvas/data/ink_recognizer/ink_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('pubspec lists the model and its notice', () {
    final assets = (loadYaml(File('pubspec.yaml').readAsStringSync())['flutter']['assets'] as List).cast<String>();
    expect(assets, contains(kBundledInkModelAsset));
    expect(assets, contains('assets/licenses/math_ink_NOTICE.txt'));
  });

  test('the bundled model is the pinned one', () {
    final bytes = File(kBundledInkModelAsset).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), kBundledInkModelSha256);
    expect(ModelFile.parse(bytes).config, isNotNull);
  });
}
