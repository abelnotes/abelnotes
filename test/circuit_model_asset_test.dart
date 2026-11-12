// The model that ships: pinned by hash, listed by name, and installed whenever
// the copy on disk is not that very file.
import 'dart:io';
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

ByteData _bytes(List<int> v) => ByteData.sublistView(Uint8List.fromList(v));

void main() {
  test('the bundled asset is the pinned model', () {
    final bytes = File(kBundledCircuitModelAsset).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), kBundledCircuitModelSha256);
    expect(ModelFile.parse(bytes).kind, 'circuit-detector');
  });

  test('pubspec names the model file, never the whole folder', () {
    final assets = (loadYaml(File('pubspec.yaml').readAsStringSync())['flutter']['assets'] as List).cast<String>();
    expect(assets, contains(kBundledCircuitModelAsset));
    expect(assets.where((a) => a.startsWith('assets/models')), [kBundledCircuitModelAsset]);
  });

  group('install', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('circuit_model');
      path = '${dir.path}/models/m.ablm';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('copies when nothing is there', () async {
      await installBundledCircuitModel(path, 'hash-a', () async => _bytes([1, 2, 3]));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('replaces a different model of the same length', () async {
      await installBundledCircuitModel(path, 'hash-a', () async => _bytes([1, 2, 3]));
      await installBundledCircuitModel(path, 'hash-b', () async => _bytes([4, 5, 6]));
      expect(File(path).readAsBytesSync(), [4, 5, 6]);
    });

    test('replaces a copy with no stamp, as older builds left it', () async {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9, 9]);
      await installBundledCircuitModel(path, 'hash-a', () async => _bytes([1, 2, 3]));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('leaves the right copy alone without reading the asset', () async {
      await installBundledCircuitModel(path, 'hash-a', () async => _bytes([1, 2, 3]));
      await installBundledCircuitModel(path, 'hash-a', () async => throw StateError('should not load'));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('a missing asset keeps what is there', () async {
      await installBundledCircuitModel(path, 'hash-a', () async => _bytes([1, 2, 3]));
      await installBundledCircuitModel(path, 'hash-b', () async => throw StateError('no asset'));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });
  });
}
