// Does the offscreen LaTeX → ui.Image pipeline actually produce an image?
// This is the fragile, recently-added part behind "paste LaTeX → symbol".

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';

void main() {
  // flutter_test does not load package fonts by default, so the KaTeX glyph
  // metrics would lay out to zero width. Register them from the bundled
  // FontManifest so the rasterize test faithfully mirrors the real app.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final family = entry['family'] as String;
      if (!family.contains('KaTeX')) continue;
      final loader = FontLoader(family);
      for (final f in (entry['fonts'] as List)) {
        loader.addFont(rootBundle.load(f['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('rasterize produces a non-empty image for display math',
      (tester) async {
    final r = await MathRasterizer.rasterize(
      latex: r'\int_0^1 x^2\,dx = \frac{1}{3}',
      color: const Color(0xFF000000),
      fontSize: 26,
      displayMode: true,
      pixelRatio: 3.0,
    );
    expect(r, isNotNull, reason: 'rasterize returned null (no view / pipeline threw)');
    expect(r!.size.width, greaterThan(0));
    expect(r.size.height, greaterThan(0));
    // The box must shrink-wrap the equation, not blow up to the layout cap.
    expect(r.size.width, lessThan(1000), reason: 'must shrink-wrap, not fill maxDim');
    expect(r.image.width, greaterThan(0));
    expect(r.image.height, greaterThan(0));
  });

  testWidgets('rasterize handles a bad latex via onErrorFallback (still non-null)',
      (tester) async {
    final r = await MathRasterizer.rasterize(
      latex: r'\frac{1}{', // malformed
      color: const Color(0xFF000000),
      fontSize: 20,
      displayMode: false,
      pixelRatio: 2.0,
    );
    expect(r, isNotNull, reason: 'fallback path should still rasterize raw text');
  });

  test('parsePastedRich turns display math into a PastedMathBlock', () {
    final blocks = parsePastedRich(r'$$\int_0^1 x^2\,dx$$');
    expect(blocks.length, 1);
    expect(blocks.first, isA<PastedMathBlock>());
    expect((blocks.first as PastedMathBlock).display, isTrue);
  });

  test('parsePastedRich recognises \\[ … \\] block math', () {
    final blocks = parsePastedRich(r'\[ a^2 + b^2 = c^2 \]');
    expect(blocks.whereType<PastedMathBlock>(), isNotEmpty);
  });

  test('parsePastedRich keeps a whole-line inline-dollar mathish as a math block', () {
    final blocks = parsePastedRich(r'$x^2 + y^2$');
    expect(blocks.whereType<PastedMathBlock>(), isNotEmpty);
  });
}
