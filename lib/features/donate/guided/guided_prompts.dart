// What the guided page asks a volunteer to write. Formulas come from
// templates filled at random (the idea of ml/src/dictation.py: vary letters,
// case, digits and structure so the model sees what it confuses); circuit
// symbols cycle through the detector's classes. See README.md.

import 'dart:math' as math;

import '../donation_sample.dart';

class GuidedPrompt {
  const GuidedPrompt(this.kind, this.label, {this.text});
  final DonationKind kind;

  /// The LaTeX, or the circuit symbol: the sample's label.
  final String label;

  /// For the symbol `text`: the label to write, e.g. R1.
  final String? text;
}

/// Every class but `junction`, a dot on a wire whose box the ink alone
/// cannot give.
const List<String> kGuidedSymbols = [
  'resistor',
  'capacitor',
  'capacitor.polarized',
  'inductor',
  'diode',
  'voltage.dc',
  'voltage.ac',
  'voltage.battery',
  'current_source',
  'transistor.bjt',
  'transistor.fet',
  'opamp',
  'ic',
  'transformer',
  'switch',
  'gnd',
  'vss',
  'crossover',
  'terminal',
  'arrow',
  'text',
];

const _textLabels = ['R1', 'R2', 'C1', 'L1', 'D1', 'Q1', 'U1', '10k', '4.7k', '100n', '5V', '12V', 'Vin', 'Vout', 'GND'];

// @-fields, filled per prompt. Several values on purpose look alike in
// handwriting (case pairs, 0 and o, 1 and l), which is where the model errs.
const Map<String, List<String>> _pools = {
  'v': ['x', 'y', 'z', 't', 'a', 'b', 'c', 'n', 'k', 'm', 'u', 'v', 'w', 'f', 'g', 'p', 'q', 'r', 's',
      'A', 'B', 'C', 'F', 'K', 'L', 'M', 'N', 'P', 'R', 'S', 'T', 'V', 'W', 'X', 'Y', 'Z'],
  'g': [r'\alpha', r'\beta', r'\gamma', r'\delta', r'\epsilon', r'\theta', r'\lambda', r'\mu', r'\pi', r'\rho',
      r'\sigma', r'\tau', r'\phi', r'\omega', r'\Omega', r'\Delta', r'\Phi', r'\xi', r'\eta', r'\zeta'],
  'i': ['i', 'j', 'k', 'n', '0', '1', '2', 'i+1', 'n-1', 'k-1', 'ij', 'in', 'out', 'max', 'C', 'x'],
  'd': ['1', '2', '3', '4', '5', '6', '7', '8', '9'],
  'n': ['0', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
  'u': ['0.5', '0,5', '2', '3', '10', '100', r'\frac{1}{2}', r'\frac{1}{4}', '0.8', '1,5', '0,25', '1'],
  'o': ['+', '-'],
  'e': ['=', '<', '>', r'\leq', r'\geq', r'\neq', r'\approx'],
  'f': [r'\sin', r'\cos', r'\tan', r'\log', r'\ln', r'\exp'],
  'm': ['0', '1', '-1', '2', '-2', '3', 'a', 'b', 'c', 'd', 'x', 'k', r'\lambda', 'a_{11}', 'a_{12}', 'a_{21}'],
  // dictation.py's pools, for its control-theory templates.
  'A': ['0.5', '0,5', '2', '3', r'\frac{1}{2}', r'\frac{1}{4}', '0.8', '1,5', 'a', 'b', r'\alpha', '0,25'],
  'B': ['0.5', '2', '1,5', r'\frac{1}{3}', '4', 'b', '0,1', r'\beta'],
  'R': ['1', '2', '0.5', r'\frac{1}{2}', '0,2', 'a', 'p', '3', '0.9', r'\frac{1}{3}'],
  'F': [r'\frac{3}{2}', r'\frac{1}{2}', r'\frac{4}{3}', '2', '0.5', r'\frac{2}{5}', '1,2', r'\frac{1}{10}'],
  'S': ['+', '-'],
};

// (weight, templates) per family.
const List<(double, List<String>)> _families = [
  (0.14, [
    r'@v_{@i}', r'@v^{@d}', r'@v_{@i}^{@d}', r'@g_{@i}', r'e^{@o@v@v}', r'@v_{@i}@o@v_{@i}=@u',
    r'x^{@d}@oy^{@d}=@v^{@d}', r'10^{-@d}', r'@v_{n+1}=@u@v_{n}', r'@v^{@d}_{@i}@o@v', r'@v^{-@d}',
    r'(@v@o@d)^{@d}', r'@v_{@i}@v_{@i}', r'@v^{@v}', r'@v^{\prime}=@u@v',
  ]),
  (0.14, [
    r'\frac{@v}{@v}', r'\frac{@d}{@v@o@d}', r'\frac{@v^{@d}}{@d}', r'\frac{d@v}{dt}', r'\frac{\partial f}{\partial @v}',
    r'\frac{1}{1+\frac{1}{@v}}', r'\frac{@v_{@i}}{@v_{@i}}=@u', r'G(s)=\frac{@d}{s(s+@d)}', r'\frac{@v@o@v}{@v@o@v}',
    r'\frac{d^{2}y}{dx^{2}}@o@dy=0', r'@v=\frac{@u}{@g}',
  ]),
  (0.06, [
    r'\sqrt{@v}', r'\sqrt{@v^{2}+@v^{2}}', r'\sqrt[@d]{@v}', r'\frac{-b\pm\sqrt{b^{2}-4ac}}{2a}',
    r'\sqrt{\frac{@v}{@v}}', r'@v=\sqrt{@d@v}',
  ]),
  (0.12, [
    r'\sum_{i=1}^{n}@v_{i}', r'\sum_{k=0}^{\infty}@v^{k}', r'\int_{0}^{@v}@v(t)dt', r'\int_{-\infty}^{\infty}e^{-x^{2}}dx',
    r'\prod_{i=1}^{n}@v_{i}', r'\lim_{x\to0}\frac{\sin x}{x}=1', r'\lim_{n\to\infty}(1+\frac{1}{n})^{n}=e',
    r'\int_{a}^{b}f(x)dx', r'\sum_{n=1}^{N}\frac{1}{n^{@d}}', r'\iint_{D}f(x,y)dxdy', r'\oint_{C}\vec{E}\cdot d\vec{l}',
    r'\int@v^{@d}d@v=\frac{@v^{@d}}{@d}+C',
  ]),
  (0.08, [
    r'\begin{pmatrix}@m&@m\\@m&@m\end{pmatrix}', r'\begin{bmatrix}@m&@m&@m\\@m&@m&@m\end{bmatrix}',
    r'\begin{bmatrix}@v\\@v\\@v\end{bmatrix}', r'\det\begin{vmatrix}@m&@m\\@m&@m\end{vmatrix}',
    r'A=\begin{pmatrix}@m&@m\\@m&@m\end{pmatrix}',
    r'\dot{x}=\begin{bmatrix}0&1\\-@d&-@d\end{bmatrix}x+\begin{bmatrix}0\\1\end{bmatrix}u',
    r'\begin{pmatrix}@m&@m&@m\\@m&@m&@m\\@m&@m&@m\end{pmatrix}',
  ]),
  (0.10, [
    r'@f(@v)', r'\sin^{2}\theta+\cos^{2}\theta=1', r'\log_{@d}@v', r'e^{j\omega t}', r'\ln(@v@o@d)',
    r'f(@v)=@v^{@d}@o@d@v', r'@f(@g t@o@g)', r'y=@ue^{-@vt}', r'\cos(@d\pi ft)', r'@f^{-1}(@v)',
  ]),
  (0.12, [
    r'@v@e@u', r'|@v|<@d', r'@v\in\mathbb{R}', r'\forall@v\in A', r'A\cup B', r'A\cap B=\emptyset',
    r'\vec{F}=m\vec{a}', r'\nabla\cdot\vec{E}=\frac{\rho}{\epsilon_{0}}', r'@v@e@v@o@d', r'\Delta@v=@v_{2}-@v_{1}',
    r'@g@e@u', r'\bar{@v}=\frac{1}{n}\sum_{i}@v_{i}', r'\hat{@v}', r'@v\to\infty',
  ]),
  // ml/src/dictation.py TEMPLATES, "k", "K", "case" and "zero".
  (0.24, [
    r'y(k)=@Ay(k-1)+@Bu(k)', r'x(k+1)=@Ax(k)+@Bu(k)', r'y(k)=@Ay(k-1)@S@Ay(k-2)+u(k-@d)',
    r'\sum_{k=0}^{\infty}@A^{k}z^{-k}', r'X(z)=\sum_{k=0}^{\infty}x(k)z^{-k}', r'(-1)^{k}@A^{k}', r'\delta(k-@d)',
    r'h(k)=@A^{k}\cdot1(k)', r'x_{k}=x_{k-1}@S@d', r'\mathbb{Z}[@A^{k}]=\frac{z}{z-@A}', r'u(k)=u(k-1)+@Ae(k)',
    r'y(k)=\frac{1}{@d}\sum_{i=0}^{k}u(i)', r'e(k)=r(k)-y(k)', r'x(k)=Ax(k-1)+Bu(k)',
    r'C(z)=K\frac{z-@R}{z-1}', r'1+KG(z)=0', r'1+K\frac{z@S@R}{(z-1)(z-@R)}=0', r'0<K<@F', r'K_{p}=@d',
    r'z^{2}+(K-@d)z+@dK=0', r'W(z)=\frac{KG(z)}{1+KG(z)}', r'C(s)=K_{p}+\frac{K_{i}}{s}', r'|K|<@d',
    r'e_{\infty}=\frac{1}{1+K}', r'P(z)=\frac{K}{z-@R}', r'G(z)=\frac{z@S@R}{(z-@R)(z@S@R)}',
    r'P(s)=\frac{@d}{s(s+@d)}', r'z=e^{sT}', r'|z|<1', r'Z(s)=R+\frac{1}{sC}', r'Z_{in}=\frac{v_{in}}{i_{in}}',
    r'Y(z)=\frac{z}{z-@R}U(z)', r'S=\frac{1}{1+C(z)P(z)}', r's=\frac{z-1}{T}', r'V_{GS}-V_{TN}',
    r'C_{GS}=\frac{2}{3}WLC_{ox}', r'|W(e^{j\omega T})|', r'P_{o}=V_{o}I_{o}', r'x(0)=@n', r'z_{0}=@R',
    r'\omega_{0}=@d0rad/s', r'10^{-@d}', r'1@n0k\Omega', r'R_{0}=@d0\Omega', r'f_{0}=@d0Hz', r'0<a<1',
    r'x(0^{+})=@n', r'2^{10}=1024', r'@d00pF', r'e^{0}=1',
  ]),
];

/// Formulas in the vocabulary the recogniser writes: no spaces except where
/// a command meets a letter.
class GuidedPrompts {
  GuidedPrompts([math.Random? random]) : _rng = random ?? math.Random();

  final math.Random _rng;
  final _seen = <String>{};
  List<String> _symbols = const [];

  /// A new prompt of [kind]; [accept] can refuse a formula (the page checks
  /// that it typesets).
  GuidedPrompt next(DonationKind kind, {bool Function(String latex)? accept}) {
    if (kind == DonationKind.circuit) {
      // Each class once per round, in a new order every round.
      if (_symbols.isEmpty) _symbols = [...kGuidedSymbols]..shuffle(_rng);
      final s = _symbols.first;
      _symbols = _symbols.sublist(1);
      return GuidedPrompt(kind, s, text: s == 'text' ? _textLabels[_rng.nextInt(_textLabels.length)] : null);
    }
    for (var tries = 0;; tries++) {
      final f = formula();
      if ((tries > 50 || _seen.add(f)) && (accept == null || accept(f))) return GuidedPrompt(kind, f);
    }
  }

  /// One filled template.
  String formula() {
    final total = _families.fold<double>(0, (s, f) => s + f.$1);
    var pick = _rng.nextDouble() * total;
    final family = _families.firstWhere((f) => (pick -= f.$1) < 0, orElse: () => _families.last).$2;
    return fill(family[_rng.nextInt(family.length)]);
  }

  String fill(String template) {
    final out = StringBuffer();
    // \alpha then x must not become \alphax, whichever side was filled in.
    void write(String part) {
      if (part.isEmpty) return;
      if (RegExp(r'\\[a-zA-Z]+$').hasMatch(out.toString()) && RegExp(r'^[a-zA-Z]').hasMatch(part)) out.write(' ');
      out.write(part);
    }

    var last = 0;
    for (final m in RegExp(r'@([a-zA-Z])').allMatches(template)) {
      write(template.substring(last, m.start));
      final pool = _pools[m.group(1)]!;
      write(pool[_rng.nextInt(pool.length)]);
      last = m.end;
    }
    write(template.substring(last));
    return out.toString();
  }
}
