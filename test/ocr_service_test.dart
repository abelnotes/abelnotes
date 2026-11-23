// The OCR service of the editor is released with the editor.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/ocr_service.dart';

void main() {
  test('the platform service can be disposed, twice', () {
    final ocr = createOcrService();
    ocr.dispose();
    ocr.dispose();
  });
}
