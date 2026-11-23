// Page previews on the web are bitmaps cached per page state. Decoding an
// image used by one page must not invalidate every other page's bitmap.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/preview_rasters.dart';

void main() {
  test('a page without images keeps its key when other images decode', () {
    final page = Object();
    final before = <String, Object?>{'other.png': null};
    final after = <String, Object?>{'other.png': Object()};
    expect(
      PreviewKey(page, 10, 10, imagesSignature(const [], before)),
      PreviewKey(page, 10, 10, imagesSignature(const [], after)),
    );
  });

  test('a page whose own image decodes gets a new key', () {
    final page = Object();
    final before = <String, Object?>{};
    final after = <String, Object?>{'mine.png': Object()};
    expect(
      PreviewKey(page, 10, 10, imagesSignature(const ['mine.png'], before)) ==
          PreviewKey(page, 10, 10, imagesSignature(const ['mine.png'], after)),
      isFalse,
    );
  });

  test('another page decoding does not touch this page\'s key', () {
    final page = Object();
    final mine = Object();
    final before = <String, Object?>{'mine.png': mine};
    final after = <String, Object?>{'mine.png': mine, 'other.png': Object()};
    expect(
      PreviewKey(page, 10, 10, imagesSignature(const ['mine.png'], before)),
      PreviewKey(page, 10, 10, imagesSignature(const ['mine.png'], after)),
    );
  });
}
