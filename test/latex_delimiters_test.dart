import 'package:abelnotes/features/canvas/data/ink_recognizer/latex_delimiters.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brackets around a matrix stretch', () {
    expect(stretchDelimiters(r'A=[\begin{matrix}1&-1\\-1&-1\end{matrix}]'),
        r'A=\left[\begin{matrix}1&-1\\-1&-1\end{matrix}\right]');
  });

  test('parentheses around a matrix and around a fraction stretch', () {
    expect(stretchDelimiters(r'(\begin{matrix}k\\t\end{matrix})'),
        r'\left(\begin{matrix}k\\t\end{matrix}\right)');
    expect(stretchDelimiters(r'(\frac{a}{b})^{2}'), r'\left(\frac{a}{b}\right)^{2}');
  });

  test('plain parentheses stay as they are', () {
    expect(stretchDelimiters(r'f(x)=(a+b)'), r'f(x)=(a+b)');
    expect(stretchDelimiters(r'[0,1]'), r'[0,1]');
  });

  test('only the pair holding tall content stretches', () {
    expect(stretchDelimiters(r'g(x)(\frac{1}{x})'), r'g(x)\left(\frac{1}{x}\right)');
  });

  test('a piecewise brace with no partner closes invisibly', () {
    expect(stretchDelimiters(r's=\{\begin{matrix}1&x>0\\0&x\le0\end{matrix}'),
        r's=\left\{\begin{matrix}1&x>0\\0&x\le0\end{matrix}\right.');
  });

  test('already stretched delimiters are left alone', () {
    const s = r'\left(\frac{a}{b}\right)';
    expect(stretchDelimiters(s), s);
  });

  test('unbalanced input does not throw', () {
    expect(stretchDelimiters(r'(\frac{a}{b}'), r'(\frac{a}{b}');
    expect(stretchDelimiters(r'\frac{a}{b})'), r'\frac{a}{b})');
  });

  test('the app renderer parses every rewritten form', () {
    for (final s in [
      r'A=[\begin{matrix}1&-1\\-1&-1\end{matrix}]',
      r'(\frac{a}{b})^{2}',
      r's=\{\begin{matrix}1&x>0\\0&x\le0\end{matrix}',
    ]) {
      expect(() => TexParser(stretchDelimiters(s), const TexParserSettings()).parse(), returnsNormally,
          reason: stretchDelimiters(s));
    }
  });

  test('open braces are closed and stray closers dropped', () {
    expect(balanceBraces(r'\frac{NW(V_{os})^{2}'), r'\frac{NW(V_{os})^{2}}{}');
    expect(balanceBraces(r'a}+b'), r'a+b');
    expect(balanceBraces(r'\{x\}'), r'\{x\}');
    expect(balanceBraces(r'\frac{a}{b}'), r'\frac{a}{b}');
    expect(() => TexParser(balanceBraces(r'I_{0}=\frac{I_{1}}{2}\frac{NW(V_{os}-V_{TW})^{2}(1+\lambda_{D2})'),
        const TexParserSettings()).parse(), returnsNormally);
  });
}
