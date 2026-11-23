import 'dart:typed_data';

import 'package:abelnotes/features/search/ink_decode.dart';
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// No native engine on this platform: handwriting is not searchable.
class InkRecognizer {
  InkRecognizer._();

  static InkRecognizer? open(Uint8List model, InkModelMeta meta, {InkLexicon? lexicon}) =>
      null;

  static Future<InkRecognizer?> load(Uint8List model, InkModelMeta meta,
          {InkLexicon? lexicon}) async =>
      null;

  Future<List<InkLine>> recognizeAsync(InkSegment seg) async => const [];

  Future<({Float32List probs, int frames, int classes, InkRaster geometry})?> debugRunAsync(
          InkSegment seg) async =>
      null;

  Future<Float32List> rasterAsync(InkSegment seg) async => Float32List(0);

  List<InkLine> recognizePage(PageData page, {bool Function(InkSegment seg)? keep}) =>
      const [];

  List<InkLine> recognize(InkSegment seg) => const [];

  void dispose() {}
}
