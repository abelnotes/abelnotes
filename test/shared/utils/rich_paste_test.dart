import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';

String _concat(PastedTextBlock b) => b.spans.map((s) => s.text).join();

void main() {
  group('detection / false positives', () {
    test('plain prose with \$ and * stays one plain block', () {
      final r = parsePastedRich('I paid \$5 for it and 3 * 4 = 12, see you * later');
      expect(r, hasLength(1));
      final b = r.first as PastedTextBlock;
      expect(b.spans, isEmpty);
      expect(b.content, 'I paid \$5 for it and 3 * 4 = 12, see you * later');
    });

    test('currency \$5 and \$10 is not math', () {
      final r = parsePastedRich('it costs \$5 and \$10 total');
      expect(r, hasLength(1));
      expect((r.first as PastedTextBlock).spans, isEmpty);
    });

    test('empty input returns a single block, never empty list', () {
      expect(parsePastedRich(''), hasLength(1));
      expect(parsePastedRich('   \n  '), hasLength(1));
    });
  });

  group('inline emphasis → spans', () {
    test('just bold', () {
      final b = parsePastedRich('**Bold title**').first as PastedTextBlock;
      expect(b.content, 'Bold title');
      expect(b.spans, hasLength(1));
      expect(b.spans.first.bold, isTrue);
      expect(_concat(b), b.content);
    });

    test('mixed bold/italic/strike/code', () {
      final b = parsePastedRich('This is **bold**, *italic*, ~~gone~~ and `code`.')
          .first as PastedTextBlock;
      expect(b.content, 'This is bold, italic, gone and code.');
      expect(_concat(b), b.content);
      expect(b.spans.firstWhere((s) => s.text == 'bold').bold, isTrue);
      expect(b.spans.firstWhere((s) => s.text == 'italic').italic, isTrue);
      expect(b.spans.firstWhere((s) => s.text == 'gone').strikethrough, isTrue);
      final code = b.spans.firstWhere((s) => s.text == 'code');
      expect(code.fontFamily, 'monospace');
    });

    test('nested bold+italic', () {
      final b = parsePastedRich('***wow*** and **a _b_ c**').first as PastedTextBlock;
      expect(_concat(b), b.content);
      expect(b.content, 'wow and a b c');
      final wow = b.spans.firstWhere((s) => s.text == 'wow');
      expect(wow.bold && wow.italic, isTrue);
      final bb = b.spans.firstWhere((s) => s.text == 'b');
      expect(bb.bold && bb.italic, isTrue);
    });

    test('intraword underscores stay literal', () {
      final r = parsePastedRich('use foo_bar_baz here **x**');
      final b = r.firstWhere((e) => e is PastedTextBlock &&
          (e).content.contains('foo_bar_baz')) as PastedTextBlock;
      expect(b.content, contains('foo_bar_baz'));
    });
  });

  group('headings', () {
    test('levels map to sizes and bold', () {
      final r = parsePastedRich('# Title\nSome intro.\n## Sub');
      expect(r.whereType<PastedTextBlock>().length, 3);
      final h1 = r[0] as PastedTextBlock;
      expect(h1.content, 'Title');
      expect(h1.fontSize, 32);
      expect(h1.spans.every((s) => s.bold), isTrue);
      final intro = r[1] as PastedTextBlock;
      expect(intro.content, 'Some intro.');
      expect(intro.spans, isEmpty); // plain
      final h2 = r[2] as PastedTextBlock;
      expect(h2.fontSize, 28);
    });
  });

  group('lists & quotes', () {
    test('unordered + nested', () {
      final b = parsePastedRich('- one\n- two\n  - two-a').first as PastedTextBlock;
      expect(b.content, '• one\n• two\n  • two-a');
      expect(b.spans, isEmpty); // all plain
    });

    test('ordered keeps numbers + inline bold', () {
      final b = parsePastedRich('1. First **item**\n2. Second').first as PastedTextBlock;
      expect(b.content, '1. First item\n2. Second');
      expect(_concat(b), b.content);
      expect(b.spans.firstWhere((s) => s.text == 'item').bold, isTrue);
    });

    test('blockquote italic', () {
      final b = parsePastedRich('> quoted *line*').first as PastedTextBlock;
      expect(b.content, '> quoted line');
      expect(_concat(b), b.content);
      expect(b.spans, isNotEmpty); // italic, not collapsed
    });
  });

  group('inline & display math', () {
    test('inline \$…\$ becomes unicode, stays one text block', () {
      final r = parsePastedRich(r'Let $\alpha^2 + \beta_i \leq \gamma$ hold.');
      expect(r, hasLength(1));
      final b = r.first as PastedTextBlock;
      expect(b.content, 'Let α² + βᵢ ≤ γ hold.');
    });

    test('whole-line \$…\$ becomes inline math block', () {
      final r = parsePastedRich(r'$E = mc^2$');
      expect(r, hasLength(1));
      final m = r.first as PastedMathBlock;
      expect(m.latex, 'E = mc^2');
      expect(m.display, isFalse);
    });

    test('display \$\$…\$\$ between prose → [text, math, text]', () {
      final r = parsePastedRich('Pythagoras:\n\$\$\na^2 + b^2 = c^2\n\$\$\nDone.');
      expect(r, hasLength(3));
      expect((r[0] as PastedTextBlock).content, 'Pythagoras:');
      final m = r[1] as PastedMathBlock;
      expect(m.latex, 'a^2 + b^2 = c^2');
      expect(m.display, isTrue);
      expect((r[2] as PastedTextBlock).content, 'Done.');
    });

    test(r'\[ … \] display block + mid-line \(\frac\) inline unicode', () {
      final r = parsePastedRich(
          '\\[ \\int_0^1 x\\,dx = \\frac{1}{2} \\]\nThe value is \\(\\frac{1}{2}\\).');
      final m = r.whereType<PastedMathBlock>().first;
      expect(m.display, isTrue);
      expect(m.latex, contains(r'\int'));
      final t = r.whereType<PastedTextBlock>().first;
      expect(t.content, 'The value is 1⁄2.');
    });
  });

  group('fenced code', () {
    test('code block is monospace, info-string dropped', () {
      final b = parsePastedRich('```dart\nvar x = 1;\n```').first as PastedTextBlock;
      expect(b.content, 'var x = 1;');
      expect(b.spans.first.fontFamily, 'monospace');
    });
  });

  group('links', () {
    test('link text kept underlined, url dropped', () {
      final b = parsePastedRich('See [the docs](https://x.io) now').first
          as PastedTextBlock;
      expect(b.content, 'See the docs now');
      expect(_concat(b), b.content);
      expect(b.spans.firstWhere((s) => s.text == 'the docs').underline, isTrue);
    });
  });

  group('latexToUnicode', () {
    test('greek + operators + super/sub', () {
      expect(latexToUnicode(r'\alpha + \beta'), 'α + β');
      expect(latexToUnicode(r'x^2'), 'x²');
      expect(latexToUnicode(r'a_i'), 'aᵢ');
      expect(latexToUnicode(r'\sum_{i=0}^{n}'), contains('∑'));
      expect(latexToUnicode(r'\sqrt{x}'), '√(x)');
      expect(latexToUnicode(r'\frac{1}{2}'), '1⁄2');
    });

    test('unmapped superscript falls back to caret notation', () {
      expect(latexToUnicode(r'x^Q'), 'x^Q');
    });

    test('unknown command keeps argument / letters', () {
      expect(latexToUnicode(r'\text{hello}'), 'hello');
      expect(latexToUnicode(r'\foo{bar}'), 'bar');
    });

    test('never throws on garbage', () {
      for (final g in [r'\frac{', r'^{', r'$$$', r'\\\\', r'{}{}{}', r'_^_^']) {
        expect(() => latexToUnicode(g), returnsNormally);
      }
    });
  });

  group('invariants & robustness', () {
    test('content == concat(spans) for every styled block', () {
      final inputs = [
        '**a** _b_ ~~c~~ `d`',
        '# H1 **bold**',
        '> q *i*',
        '1. one\n2. **two**',
        'See [x](http://y.z) and `code`',
      ];
      for (final inp in inputs) {
        for (final blk in parsePastedRich(inp).whereType<PastedTextBlock>()) {
          if (blk.spans.isNotEmpty) {
            expect(_concat(blk), blk.content, reason: 'invariant for: $inp');
          }
        }
      }
    });

    test('never throws on random/garbled input', () {
      final inputs = [
        '**unclosed', '`code', '\$x^', '[link](', '~~~~~', r'\(\(\(',
        '###### ', '\$\$\n\n', '- \n- \n', 'a\\* literal *x',
      ];
      for (final inp in inputs) {
        expect(() => parsePastedRich(inp), returnsNormally, reason: inp);
        expect(parsePastedRich(inp), isNotEmpty);
      }
    });
  });
}
