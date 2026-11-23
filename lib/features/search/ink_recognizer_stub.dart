import 'dart:typed_data';

import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// No native engine on this platform: handwriting is not searchable.
class InkRecognizer {
  InkRecognizer._();

  static InkRecognizer? open(Uint8List model, InkModelMeta meta) => null;

  List<InkLine> recognizePage(PageData page) => const [];

  InkLine? recognize(InkSegment seg) => null;

  void dispose() {}
}
