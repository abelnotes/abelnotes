// Tests for the rich-text feature: per-char style splicing, span
// run-length encoding, HTML clipboard conversion, and .ncnote JSON
// round-trip of TextSpanData.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/text_editor_dialog.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/html_text.dart';

const bold = TextSpanData(text: '', bold: true);

void main() {
  group('spliceCharStyles', () {
    test('typing inherits the style left of the caret', () {
      // "ab" both bold, type 'c' at end → 'c' bold too.
      final out = spliceCharStyles('ab', 'abc', [bold, bold]);
      expect(out.length, 3);
      expect(out[2].bold, isTrue);
    });

    test('delete in the middle removes matching styles', () {
      final styles = [kPlainCharStyle, bold, kPlainCharStyle];
      final out = spliceCharStyles('abc', 'ac', styles);
      expect(out.length, 2);
      expect(out[0].bold, isFalse);
      expect(out[1].bold, isFalse);
    });

    test('bulk replace (autocorrect-style) keeps surrounding styles', () {
      // "xy" plain + "Z" bold → replace middle: "xKKy"... use clear case:
      final styles = [bold, kPlainCharStyle, kPlainCharStyle, bold];
      final out = spliceCharStyles('abcd', 'aXYZd', styles);
      expect(out.length, 5);
      expect(out.first.bold, isTrue); // 'a' untouched
      expect(out.last.bold, isTrue); // 'd' untouched
    });

    test('explicit insertStyle wins over inheritance', () {
      final out = spliceCharStyles('aa', 'aba', [kPlainCharStyle, kPlainCharStyle],
          insertStyle: bold);
      expect(out.length, 3);
      expect(out[1].bold, isTrue);
    });
  });

  group('encode/expand spans', () {
    test('all-plain encodes to empty (legacy form)', () {
      expect(encodeSpans('ciao', List.filled(4, kPlainCharStyle)), isEmpty);
    });

    test('round-trips mixed styles', () {
      final styles = [bold, bold, kPlainCharStyle, kPlainCharStyle];
      final spans = encodeSpans('ciao', styles);
      expect(spans.length, 2);
      expect(spans[0].text, 'ci');
      expect(spans[0].bold, isTrue);
      expect(spans[1].text, 'ao');
      final back = expandSpans('ciao', spans);
      expect(back, isNotNull);
      expect(back!.length, 4);
      expect(back[0].bold, isTrue);
      expect(back[3].bold, isFalse);
    });

    test('expandSpans rejects mismatched coverage', () {
      expect(expandSpans('ciaoX', [bold.copyWith(text: 'ciao')]), isNull);
    });
  });

  group('htmlToSpans', () {
    test('keeps bold and italic from b/strong/i/em', () {
      final r = htmlToSpans('Hello <b>bold</b> and <em>italic</em>!');
      expect(r, isNotNull);
      expect(r!.plain, 'Hello bold and italic!');
      final boldSpan = r.spans.firstWhere((s) => s.bold);
      expect(boldSpan.text, 'bold');
      final italSpan = r.spans.firstWhere((s) => s.italic);
      expect(italSpan.text, 'italic');
    });

    test('paragraphs and br become newlines, entities decode', () {
      final r = htmlToSpans('<p>uno&nbsp;&amp; due</p><p>tre<br>quattro</p>');
      expect(r, isNotNull);
      expect(r!.plain, contains('uno & due'));
      expect(r.plain, contains('tre\nquattro'));
    });

    test('style/script content is dropped', () {
      final r = htmlToSpans(
          '<style>.x{color:red}</style><b>ok</b><script>var a=1;</script>');
      expect(r!.plain, 'ok');
    });

    test('plain string without tags returns null', () {
      expect(htmlToSpans('no markup here'), isNull);
    });
  });

  group('.ncnote JSON round-trip with spans', () {
    test('spans survive compactPageJson + decodePageData', () {
      final page = PageData(
        pageId: 'p1',
        pageNumber: 1,
        width: 800,
        height: 1100,
        layers: RenderingLayers(
          background: const BackgroundLayer(),
          content: [
            ContentElement.text(
              id: 't1',
              zIndex: 1,
              data: const TextData(
                x: 10, y: 20, width: 300, height: 50,
                content: 'ciao mondo',
                spans: [
                  TextSpanData(text: 'ciao ', bold: true),
                  TextSpanData(text: 'mondo', italic: true, color: 0xFFFF0000),
                ],
              ),
            ),
          ],
        ),
        createdAt: DateTime.utc(2026),
        modifiedAt: DateTime.utc(2026),
      );

      final decoded = decodePageData(
          jsonDecode(compactPageJson(page)) as Map<String, dynamic>);
      final el = decoded.layers.content.single as TextElement;
      expect(el.data.content, 'ciao mondo');
      expect(el.data.spans.length, 2);
      expect(el.data.spans[0].bold, isTrue);
      expect(el.data.spans[1].italic, isTrue);
      expect(el.data.spans[1].color, 0xFFFF0000);
    });

    test('per-span fontFamily survives round-trip', () {
      final page = PageData(
        pageId: 'p1', pageNumber: 1, width: 800, height: 1100,
        layers: RenderingLayers(
          background: const BackgroundLayer(),
          content: [
            ContentElement.text(
              id: 't1', zIndex: 1,
              data: const TextData(
                x: 0, y: 0, width: 300, height: 50, content: 'run code()',
                spans: [
                  TextSpanData(text: 'run '),
                  TextSpanData(text: 'code()', fontFamily: 'monospace', color: _codeColor),
                ],
              ),
            ),
          ],
        ),
        createdAt: DateTime.utc(2026), modifiedAt: DateTime.utc(2026),
      );
      final decoded = decodePageData(
          jsonDecode(compactPageJson(page)) as Map<String, dynamic>);
      final el = decoded.layers.content.single as TextElement;
      expect(el.data.spans[1].fontFamily, 'monospace');
      expect(el.data.spans[1].color, _codeColor);
      expect(el.data.spans.map((s) => s.text).join(), el.data.content);
    });

    test('MathElement round-trips its latex + style losslessly', () {
      final page = PageData(
        pageId: 'p1', pageNumber: 1, width: 800, height: 1100,
        layers: RenderingLayers(
          background: const BackgroundLayer(),
          content: [
            ContentElement.math(
              id: 'm1', zIndex: 3,
              data: const MathData(
                x: 12, y: 34, width: 120, height: 48,
                latex: r'\frac{1}{2}\sum_{i=0}^{n} x_i',
                displayMode: true, color: 0xFF112233, fontSize: 26,
              ),
            ),
          ],
        ),
        createdAt: DateTime.utc(2026), modifiedAt: DateTime.utc(2026),
      );
      final raw = jsonDecode(compactPageJson(page)) as Map<String, dynamic>;
      // Union tag must be present for old/new client dispatch.
      final elJson = (raw['layers']['content'] as List).single as Map;
      expect(elJson['type'], 'math');
      final decoded = decodePageData(raw);
      final el = decoded.layers.content.single as MathElement;
      expect(el.id, 'm1');
      expect(el.zIndex, 3);
      expect(el.data.latex, r'\frac{1}{2}\sum_{i=0}^{n} x_i');
      expect(el.data.displayMode, isTrue);
      expect(el.data.color, 0xFF112233);
      expect(el.data.fontSize, 26);
      expect(el.data.width, 120);
      expect(el.data.height, 48);
    });
  });
}

/// Mirror of the inline-code color used by rich_paste.dart (private there).
const int _codeColor = 0xFF8E24AA;
