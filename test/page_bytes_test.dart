// Stored page bytes: the binary form must read back exactly what the compact
// JSON reads back, damage must look like damage (FormatException), and a
// later binary format must never look like damage.

import 'dart:convert';
import 'dart:typed_data';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter_test/flutter_test.dart';

ContentElement _stroke(String id, List<StrokePoint> points) =>
    ContentElement.stroke(id: id, zIndex: 0, data: StrokeData(points: points));

PageData _page(List<ContentElement> content) => PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
    );

PageData _viaJson(PageData page) =>
    decodePageBytes(utf8.encode(compactPageJson(page)));

void main() {
  final rich = _page([
    _stroke('plain', const [StrokePoint(x: 1.5, y: 2), StrokePoint(x: 3, y: 4)]),
    _stroke('pressure', const [
      StrokePoint(x: 10.12345, y: 20.98765, pressure: 0.25),
      StrokePoint(x: 11, y: 21, pressure: 0.5004),
    ]),
    _stroke('tilt', const [StrokePoint(x: -5.5, y: -0.0004, tilt: 0.3)]),
    _stroke('time', const [
      StrokePoint(x: 6000, y: 5999.999, pressure: 0.9, timestamp: 1730000000000),
      StrokePoint(x: 0, y: 0, timestamp: -3),
    ]),
    _stroke('empty', const []),
    const ContentElement.text(
        id: 't', zIndex: 1, data: TextData(x: 1, y: 2, width: 10, height: 10, content: 'h"i "points":[]')),
    const ContentElement.image(
        id: 'i', zIndex: 2, data: ImageData(x: 0.1234, y: 0, width: 10, height: 10, assetPath: 'a.png')),
    const ContentElement.unknown(id: 'u', zIndex: 3, raw: {'type': 'future', 'points': [1, 2]}),
  ]);

  test('binary reads back what the compact JSON reads back', () {
    final bin = binaryPageBytes(rich)!;
    expect(isBinaryPage(bin), isTrue);
    expect(decodePageBytes(bin), _viaJson(rich));
    expect(compactPageJson(decodePageBytes(bin)), compactPageJson(rich));
    final blank = _page(const []);
    expect(decodePageBytes(binaryPageBytes(blank)!), _viaJson(blank));
  });

  test('JSON pages still read, and are what is written for now', () {
    final js = utf8.encode(compactPageJson(rich));
    expect(isBinaryPage(js), isFalse);
    expect(decodePageBytes(js), _viaJson(rich));
    expect(encodePageBytes(rich), js);
  });

  test('a cut-off or garbled binary page is a FormatException', () {
    final bin = binaryPageBytes(rich)!;
    for (final cut in [5, 6, bin.length ~/ 3, bin.length ~/ 2, bin.length - 1]) {
      expect(() => decodePageBytes(Uint8List.sublistView(bin, 0, cut)),
          throwsFormatException, reason: 'cut at $cut');
    }
    final extra = Uint8List.fromList([...bin, 0]);
    expect(() => decodePageBytes(extra), throwsFormatException);
    final bad = Uint8List.fromList(bin)..[4] = 0;
    expect(() => decodePageBytes(bad), throwsFormatException);
  });

  test('a binary page of a later format is not taken for a damaged one', () {
    final later = Uint8List.fromList(binaryPageBytes(rich)!)..[4] = 2;
    expect(() => decodePageBytes(later), throwsA(isA<PageFormatTooNewException>()));
  });

  test('non-finite points have no binary form', () {
    expect(binaryPageBytes(_page([_stroke('n', const [StrokePoint(x: double.nan, y: 0)])])), isNull);
  });

  test('a long stroke round-trips', () {
    final pts = [
      for (var i = 0; i < 5000; i++)
        StrokePoint(x: i * 0.37, y: 300 - i * 0.011, pressure: (i % 97) / 97, timestamp: i * 4),
    ];
    final page = _page([_stroke('long', pts)]);
    final bin = binaryPageBytes(page)!;
    expect(decodePageBytes(bin), _viaJson(page));
    expect(bin.length, lessThan(utf8.encode(compactPageJson(page)).length ~/ 2));
  });
}
