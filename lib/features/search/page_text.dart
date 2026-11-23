import 'dart:convert';
import 'dart:typed_data';

import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/text_fold.dart';

/// Which kind of content a piece of indexed text came from (bit flags).
class TextSource {
  static const text = 1;
  static const math = 2;
  static const pdf = 4;
  static const ink = 8; // recognised handwriting
  static const chapter = 16;
}

/// The searchable text of one page: [raw] to show, [folded] to match, one
/// line each and in step. [parts] counts lines per source (text,math,pdf,ink).
/// [ink] holds the handwritten lines with their geometry (InkLine JSON).
class PageText {
  final String raw;
  final String folded;
  final int sources;
  final String parts;
  final String ink;
  const PageText(this.raw, this.folded, this.sources, this.parts, {this.ink = ''});

  static const empty = PageText('', '', 0, '0,0,0');
  bool get isEmpty => raw.isEmpty;

  /// This text plus recognised handwriting, one line each, after the rest.
  PageText withInk(List<InkLine> lines) {
    final r = [if (raw.isNotEmpty) raw], f = [if (folded.isNotEmpty) folded];
    var n = 0;
    for (final l in lines) {
      final t = l.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) continue;
      r.add(t);
      f.add(foldForSearch(t));
      n++;
    }
    if (n == 0) return this;
    final p = parts.split(',');
    while (p.length < 3) {
      p.add('0');
    }
    return PageText(r.join('\n'), f.join('\n'), sources | TextSource.ink,
        '${p[0]},${p[1]},${p[2]},$n',
        ink: InkLine.encodeAll(lines));
  }
}

/// Text of a decoded page: typed text boxes, LaTeX and the PDF text layer.
PageText extractPageText(PageData page) => _compose(
      [
        for (final e in page.layers.content)
          if (e is TextElement) e.data.content,
      ],
      [
        for (final e in page.layers.content)
          if (e is MathElement) e.data.latex,
      ],
      [for (final r in page.pdfTextLayer?.runs ?? const <PdfTextRun>[]) r.text],
    );

/// Same as [extractPageText] straight from stored page bytes (JSON or the
/// binary form), without decoding strokes. Throws [FormatException] on a
/// page it cannot read.
PageText extractPageTextFromBytes(List<int> bytes) {
  final json = _pageJson(bytes);
  final texts = <String>[], maths = <String>[], pdf = <String>[];
  final layers = json['layers'];
  final content = layers is Map ? layers['content'] : null;
  if (content is List) {
    for (final e in content) {
      if (e is! Map) continue;
      final data = e['data'];
      if (data is! Map) continue;
      final type = e['type'];
      if (type == 'text' && data['content'] is String) {
        texts.add(data['content'] as String);
      } else if (type == 'math' && data['latex'] is String) {
        maths.add(data['latex'] as String);
      }
    }
  }
  final layer = json['pdfTextLayer'];
  final runs = layer is Map ? layer['runs'] : null;
  if (runs is List) {
    for (final r in runs) {
      if (r is Map && r['text'] is String) pdf.add(r['text'] as String);
    }
  }
  return _compose(texts, maths, pdf);
}

Map<String, dynamic> _pageJson(List<int> bytes) {
  // Binary form: "ABPG", version, varint length, JSON without stroke points.
  if (bytes.length > 5 &&
      bytes[0] == 0x41 &&
      bytes[1] == 0x42 &&
      bytes[2] == 0x50 &&
      bytes[3] == 0x47) {
    if (bytes[4] != 1) throw const FormatException('page format not readable');
    var pos = 5, len = 0, scale = 1;
    while (true) {
      final x = bytes[pos++];
      len += (x % 0x80) * scale;
      if (x < 0x80) break;
      scale *= 0x80;
    }
    if (pos + len > bytes.length) throw const FormatException('truncated');
    bytes = Uint8List.sublistView(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes), pos, pos + len);
  }
  final v = jsonDecode(utf8.decode(bytes));
  if (v is! Map<String, dynamic>) throw const FormatException('not a page');
  return v;
}

PageText _compose(List<String> texts, List<String> maths, List<String> pdf) {
  final raw = <String>[], folded = <String>[];
  var sources = 0;
  var nText = 0, nMath = 0, nPdf = 0;
  String line(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final t in texts) {
    final l = line(t);
    if (l.isEmpty) continue;
    raw.add(l);
    folded.add(foldForSearch(l));
    nText++;
  }
  for (final m in maths) {
    final l = line(m);
    final words = latexWords(l);
    if (words.isEmpty) continue;
    raw.add(l);
    folded.add(foldForSearch(words));
    nMath++;
  }
  // PDF runs are line fragments: one joined line keeps phrases searchable.
  final pdfLine = line(pdf.join(' '));
  if (pdfLine.isNotEmpty) {
    raw.add(pdfLine);
    folded.add(foldForSearch(pdfLine));
    nPdf = 1;
  }
  if (nText > 0) sources |= TextSource.text;
  if (nMath > 0) sources |= TextSource.math;
  if (nPdf > 0) sources |= TextSource.pdf;
  if (raw.isEmpty) return PageText.empty;
  return PageText(
      raw.join('\n'), folded.join('\n'), sources, '$nText,$nMath,$nPdf');
}

// Commands whose name is a word a person would search for.
const _wordCommands = {
  'alpha',
  'beta',
  'gamma',
  'delta',
  'epsilon',
  'varepsilon',
  'zeta',
  'eta',
  'theta',
  'vartheta',
  'iota',
  'kappa',
  'lambda',
  'mu',
  'nu',
  'xi',
  'pi',
  'varpi',
  'rho',
  'varrho',
  'sigma',
  'varsigma',
  'tau',
  'upsilon',
  'phi',
  'varphi',
  'chi',
  'psi',
  'omega',
  'Gamma',
  'Delta',
  'Theta',
  'Lambda',
  'Xi',
  'Pi',
  'Sigma',
  'Upsilon',
  'Phi',
  'Psi',
  'Omega',
  'sin',
  'cos',
  'tan',
  'cot',
  'sec',
  'csc',
  'sinh',
  'cosh',
  'tanh',
  'arcsin',
  'arccos',
  'arctan',
  'log',
  'ln',
  'exp',
  'lim',
  'max',
  'min',
  'det',
  'infty',
  'partial',
  'nabla',
  'hbar',
};

final _latexToken = RegExp(r'\\([A-Za-z]+)|[A-Za-z]+|[0-9]+(?:[.,][0-9]+)?');

/// The words of a LaTeX source: letters, numbers and the names of Greek
/// letters and functions; other commands, braces and ^ _ are dropped.
String latexWords(String latex) {
  final out = <String>[];
  for (final m in _latexToken.allMatches(latex)) {
    final cmd = m.group(1);
    if (cmd != null) {
      if (_wordCommands.contains(cmd)) out.add(cmd);
    } else {
      out.add(m.group(0)!);
    }
  }
  return out.join(' ');
}
