import 'dart:io';

/// Folder with ML data and exported models, outside the repo.
/// `ABELNOTES_ML` overrides the default `~/abelnotes-ml`.
String mlDir() =>
    Platform.environment['ABELNOTES_ML'] ?? '${Platform.environment['HOME']}/abelnotes-ml';

/// Exported formula model with test vectors (ml/README.md), f32 first
/// since f16 needs a tolerance loose enough to hide a porting bug.
/// `ABELNOTES_ML_DART` overrides the search.
String? inkExportDir() {
  final override = Platform.environment['ABELNOTES_ML_DART'];
  for (final dir in [
    if (override != null && override.isNotEmpty) override,
    '${mlDir()}/out/formula/dart-f32',
    '${mlDir()}/out/formula/dart',
  ]) {
    if (File('$dir/weights.bin').existsSync() && File('$dir/testvectors.bin').existsSync()) return dir;
  }
  return null;
}
