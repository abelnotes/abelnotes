import 'dart:io';

/// Folder with ML data and exported models, outside the repo.
/// `ABELNOTES_ML` overrides the default `~/abelnotes-ml`.
String mlDir() =>
    Platform.environment['ABELNOTES_ML'] ?? '${Platform.environment['HOME']}/abelnotes-ml';
