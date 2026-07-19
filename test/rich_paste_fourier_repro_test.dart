import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';

void main() {
  test('repro: Fourier paste — mixed prose + inline math + display block',
      () {
    const text = 'La formula generale\n'
        r"Data una funzione $f(x)$ definita nell'intervallo $[ -L, L ]$ e periodica con periodo $T = 2L$, la serie di Fourier è espressa come:"
        '\n'
        r'$$f(x) \sim \frac{a_0}{2} + \sum_{n=1}^{\infty} \left( a_n \cos\left( \frac{n \pi x}{L} \right) + b_n \sin\left( \frac{n \pi x}{L} \right) \right)$$';

    final blocks = parsePastedRich(text);
    for (final b in blocks) {
      if (b is PastedTextBlock) {
        // ignore: avoid_print
        print('TEXT: "${b.content}" spans=${b.spans.length}');
      } else if (b is PastedMathBlock) {
        // ignore: avoid_print
        print('MATH(display=${b.display}): ${b.latex}');
      }
    }

    final mathBlocks = blocks.whereType<PastedMathBlock>().toList();
    expect(mathBlocks, hasLength(1),
        reason: r'the $$…$$ line must become exactly one math block');
    expect(mathBlocks.first.display, isTrue);
    expect(mathBlocks.first.latex, contains(r'\sum_{n=1}^{\infty}'));
    expect(mathBlocks.first.latex, contains(r'\frac{a_0}{2}'));
  });


  test(r'display math embedded mid-line (prose before $$…$$ on same line)',
      () {
    const text =
        r'la serie di Fourier è espressa come: $$f(x) \sim \frac{a_0}{2} + \sum_{n=1}^{\infty} a_n$$';
    final blocks = parsePastedRich(text);
    final math = blocks.whereType<PastedMathBlock>().toList();
    expect(math, hasLength(1));
    expect(math.first.latex, contains(r'\frac{a_0}{2}'));
  });

  test('display math with trailing punctuation after closing delimiters', () {
    const text = 'Intro:\n'
        r'$$f(x) \sim \frac{a_0}{2} + \sum_{n=1}^{\infty} a_n$$.';
    final blocks = parsePastedRich(text);
    final math = blocks.whereType<PastedMathBlock>().toList();
    expect(math, hasLength(1));
  });

  test(r'inline $f(x)$ and $[ -L, L ]$ recognized as mathish', () {
    const text =
        r'Data una funzione $f(x)$ definita in $[ -L, L ]$ e periodica.';
    final blocks = parsePastedRich(text);
    expect(blocks, hasLength(1));
    final t = blocks.first as PastedTextBlock;
    expect(t.content, isNot(contains(r'$')));
  });

  test('repro: bare [ … ] display math (lost backslash from web copy)', () {
    // Common artifact copying rendered LaTeX out of ChatGPT/web UIs: the
    // backslash before \[ \] is dropped, leaving plain brackets, and the
    // body keeps a trailing "," from an equation-array-style source.
    const text = '[\n'
        r'f(x) = \frac{a_0}{2} + \sum_{n=1}^{\infty} \left( a_n \cos\left(\frac{n\pi x}{L}\right) + b_n \sin\left(\frac{n\pi x}{L}\right) \right),'
        '\n]';
    final blocks = parsePastedRich(text);
    final math = blocks.whereType<PastedMathBlock>().toList();
    expect(math, hasLength(1));
    expect(math.first.display, isTrue);
    expect(math.first.latex, contains(r'\frac{a_0}{2}'));
    expect(math.first.latex, contains(r'\sum_{n=1}^{\infty}'));
    expect(math.first.latex, isNot(endsWith(',')),
        reason: 'trailing comma from the equation-array source is noise');
  });

  test('bare [ ] brackets with non-LaTeX content stay plain text', () {
    const text = '[\nsee note 1\n]';
    final blocks = parsePastedRich(text);
    expect(blocks.whereType<PastedMathBlock>(), isEmpty);
  });
}
