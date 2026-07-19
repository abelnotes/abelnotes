// ═══════════════════════════════════════════════════════════════
//  rich_paste.dart
//
//  Best-effort conversion of pasted PLAIN text containing Markdown and
//  LaTeX into a vertical sequence of canvas blocks: styled text runs
//  (PastedTextBlock) and typeset-math blocks (PastedMathBlock). Inline
//  $…$ math is converted to a best-effort Unicode string spliced into
//  the prose so the text stays one editable element; display $$…$$ /
//  \[…\] (and whole-line $…$ / \(…\)) become typeset math blocks.
//
//  Pure Dart — unit-testable without Flutter. NEVER throws: any parse
//  oddity degrades to a single plain text block. Mirrors the contract
//  and style of html_text.dart (RLE into spans; all-plain → empty spans).
// ═══════════════════════════════════════════════════════════════

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Inline `code` color (distinct purple) so code reads as code even before
/// the per-span monospace font renders.
const int _codeColor = 0xFF8E24AA;

/// One vertically-stacked block produced from pasted plain text.
sealed class PastedBlock {
  const PastedBlock();
}

/// A run of prose/heading/list/quote. [content] is the plain text;
/// invariant: `content == spans.map((s) => s.text).join('')` when [spans]
/// is non-empty. [spans] is EMPTY when the block is all-plain (legacy
/// rendering path, same contract as htmlToSpans). [fontSize] is the
/// element base size; headings raise it. [alignment] is always 'left'.
final class PastedTextBlock extends PastedBlock {
  final String content;
  final List<TextSpanData> spans;
  final double fontSize;
  final String alignment;
  const PastedTextBlock({
    required this.content,
    required this.spans,
    this.fontSize = 16.0,
    this.alignment = 'left',
  });
}

/// A typeset-math block. [latex] is the RAW LaTeX source WITHOUT delimiters
/// ($$, \[, $, \( stripped). [display] = true for $$…$$ / \[…\] (block),
/// false for a whole-line $…$ / \(…\) promoted to its own block.
final class PastedMathBlock extends PastedBlock {
  final String latex;
  final bool display;
  const PastedMathBlock({required this.latex, this.display = true});
}

// ── Detection regexes (line-anchored) ──
final RegExp _reHeading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*)$');
final RegExp _reUList = RegExp(r'^(\s*)[-*+]\s+(\S.*)$');
final RegExp _reOList = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(\S.*)$');
final RegExp _reQuote = RegExp(r'^(\s*)>\s?(.*)$');
final RegExp _reFence = RegExp(r'^\s*(```|~~~)');
final RegExp _reLatexCmd = RegExp(
    r'\\(frac|sqrt|sum|prod|int|oint|alpha|beta|gamma|delta|epsilon|theta|lambda|mu|nu|pi|rho|sigma|tau|phi|chi|psi|omega|Gamma|Delta|Theta|Lambda|Sigma|Omega|leq|geq|neq|approx|equiv|infty|partial|nabla|vec|hat|bar|tilde|dot|text|mathrm|mathbb|mathbf|mathit|operatorname|begin|end|left|right|cdot|times|div|pm|mp|times|in|notin|subset|cup|cap|forall|exists|rightarrow|leftarrow|leftrightarrow|Rightarrow|to|mapsto|ldots|cdots|dots)\b');
final RegExp _reLink = RegExp(r'\[([^\]]*)\]\(([^)\s]+)\)');

bool _isAlnum(String c) =>
    c.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(c);

const String _mdPunct = r"\`*_{}[]()#+-.!~>$";
bool _isMdPunct(String c) => c.length == 1 && _mdPunct.contains(c);

/// True when a `$…$` inner string looks like math (vs. currency/prose).
bool _isMathish(String s) {
  if (s.trim().isEmpty) return false;
  if (RegExp(r'\\[a-zA-Z]').hasMatch(s)) return true; // a command
  if (RegExp(r'[\^_=]').hasMatch(s)) return true; // super/sub/relation
  if (RegExp(r'[{}]').hasMatch(s)) return true;
  // a letter/number, an operator, then another → "x + y", "2*n"
  if (RegExp(r'[A-Za-z0-9]\s*[+\-*/]\s*[A-Za-z0-9]').hasMatch(s)) return true;
  // single-letter function application → "f(x)", "g(t)"
  if (RegExp(r'(?:^|[^A-Za-z])[A-Za-z]\s*\([^()]*\)').hasMatch(s)) return true;
  // interval / tuple literal → "[ -L, L ]", "(0, 2L)"
  if (RegExp(r'^[\[(][^\[\]()]*,[^\[\]()]*[\])]$').hasMatch(s.trim())) {
    return true;
  }
  return false;
}

/// Heading font sizes by ATX level (1..6), relative to a 16px base.
const List<double> _headingSizes = [32, 28, 24, 20, 18, 16];

/// Heuristic: does [text] contain real Markdown/LaTeX worth parsing? Avoids
/// false positives on prose with a stray asterisk or a lone `$5`.
bool _detectRich(String text) {
  if (text.trim().isEmpty) return false;
  final lines = text.split('\n');
  for (final raw in lines) {
    final line = raw;
    if (_reHeading.hasMatch(line)) return true;
    if (_reUList.hasMatch(line)) return true;
    if (_reOList.hasMatch(line)) return true;
    if (_reQuote.hasMatch(line) && line.trim().length > 1) return true;
    if (_reFence.hasMatch(line)) return true;
    final t = line.trim();
    if (t == r'$$' || RegExp(r'^\$\$.*\$\$$').hasMatch(t)) return true;
    // embedded $$…$$ with mathish content (prose on the same line)
    for (final m in RegExp(r'\$\$(.+?)\$\$').allMatches(line)) {
      if (_isMathish(m.group(1)!)) return true;
    }
    if (t.startsWith(r'\[') || t.endsWith(r'\]')) return true;
    if (_reLatexCmd.hasMatch(line)) return true;
    if (RegExp(r'\\\(.+?\\\)').hasMatch(line)) return true;
    // balanced emphasis pair (non-space inner, no intraword arithmetic)
    if (RegExp(r'(\*\*|__|\*|_|~~)(?! )[^\n]*?\S\1').hasMatch(line) &&
        _hasRealEmphasis(line)) {
      return true;
    }
    if (RegExp(r'`[^`\n]+`').hasMatch(line)) return true;
    if (_reLink.hasMatch(line)) return true;
    // inline math: a $…$ pair whose inner is mathish
    for (final m in RegExp(r'\$([^$\n]+)\$').allMatches(line)) {
      if (_isMathish(m.group(1)!)) return true;
    }
  }
  return false;
}

/// Guards the emphasis probe against arithmetic like `3 * 4 = 12`: requires
/// a delimiter immediately followed by a non-space AND closed by a
/// delimiter immediately preceded by a non-space.
bool _hasRealEmphasis(String line) {
  return RegExp(r'(\*\*|\*|__|_|~~)(?=\S)(?:(?!\1).)*?\S\1').hasMatch(line);
}

/// Parse pasted PLAIN text into an ordered, top-to-bottom list of blocks.
/// NEVER throws and NEVER returns empty: non-markdown prose (or any parse
/// failure) degrades to a single PastedTextBlock(content: text, spans: []).
List<PastedBlock> parsePastedRich(String text) {
  if (text.trim().isEmpty) {
    return [PastedTextBlock(content: text, spans: const [])];
  }
  if (!_detectRich(text)) {
    return [PastedTextBlock(content: text, spans: const [])];
  }
  try {
    final blocks = _segment(text);
    if (blocks.isEmpty) {
      return [PastedTextBlock(content: text, spans: const [])];
    }
    return blocks;
  } catch (_) {
    return [PastedTextBlock(content: text, spans: const [])];
  }
}

List<PastedBlock> _segment(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <PastedBlock>[];
  final region = <TextSpanData>[];

  void flushRegion() {
    if (region.isEmpty) return;
    final block = _finishTextBlock(List.of(region), 16.0);
    if (block != null) blocks.add(block);
    region.clear();
  }

  void addRegionLine(List<TextSpanData> lineSpans) {
    if (region.isNotEmpty) {
      region.add(const TextSpanData(text: '\n'));
    }
    region.addAll(lineSpans);
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    // ── Fenced code block ──
    final fence = _reFence.firstMatch(line);
    if (fence != null) {
      flushRegion();
      final marker = fence.group(1)!;
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length && !lines[j].trimLeft().startsWith(marker)) {
        body.add(lines[j]);
        j++;
      }
      final code = body.join('\n');
      if (code.isNotEmpty) {
        blocks.add(PastedTextBlock(
          content: code,
          spans: [
            TextSpanData(text: code, fontFamily: 'monospace', color: _codeColor)
          ],
        ));
      }
      i = j < lines.length ? j + 1 : j;
      continue;
    }

    // ── Display math: opening `$$` fence ──
    if (trimmed == r'$$') {
      flushRegion();
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length && lines[j].trim() != r'$$') {
        body.add(lines[j]);
        j++;
      }
      final latex = body.join('\n').trim();
      if (latex.isNotEmpty) {
        blocks.add(PastedMathBlock(latex: latex, display: true));
      }
      i = j < lines.length ? j + 1 : j;
      continue;
    }
    // single-line $$ … $$ (whole line: unconditional, as before)
    final singleDisp = RegExp(r'^\s*\$\$(.+)\$\$\s*$').firstMatch(line);
    if (singleDisp != null) {
      flushRegion();
      blocks.add(PastedMathBlock(latex: singleDisp.group(1)!.trim(), display: true));
      i++;
      continue;
    }
    // $$ … $$ embedded in a prose line ("…espressa come: $$f(x)…$$." —
    // ChatGPT/web copies often keep the intro sentence, or a trailing
    // period, on the same line). Split: prose stays text, each mathish
    // $$…$$ becomes its own display block. Guarded by _isMathish so
    // "$$5 tip$$"-style prose never typesets.
    final embedded = RegExp(r'\$\$(.+?)\$\$')
        .allMatches(line)
        .where((m) => _isMathish(m.group(1)!))
        .toList();
    if (embedded.isNotEmpty) {
      var cursor = 0;
      for (final m in embedded) {
        final before = line.substring(cursor, m.start);
        if (before.trim().isNotEmpty) addRegionLine(_renderLine(before));
        flushRegion();
        blocks.add(PastedMathBlock(latex: m.group(1)!.trim(), display: true));
        cursor = m.end;
      }
      final after = line.substring(cursor);
      // Drop a bare trailing "."/",…" left over after the closing $$ —
      // it belonged to the sentence typographically, not to the content.
      if (after.trim().isNotEmpty &&
          !RegExp(r'^[\s.,;:!?]*$').hasMatch(after)) {
        addRegionLine(_renderLine(after));
      }
      i++;
      continue;
    }
    // ── Display math: bare `[` … `]` fence ──
    // Common artifact from copying rendered LaTeX out of ChatGPT/web UIs:
    // the backslash before \[ \] gets dropped, leaving plain brackets on
    // their own lines. A lone "[" is too common in ordinary prose/citations
    // to hijack unconditionally, so this only fires when the enclosed body
    // actually contains a LaTeX command.
    if (trimmed == '[') {
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length && lines[j].trim() != ']') {
        body.add(lines[j]);
        j++;
      }
      final joined = body.join('\n');
      if (j < lines.length && _reLatexCmd.hasMatch(joined)) {
        flushRegion();
        // Drop a bare trailing "," left over from equation-array sources.
        final latex =
            joined.trim().replaceFirst(RegExp(r',\s*$'), '');
        if (latex.isNotEmpty) {
          blocks.add(PastedMathBlock(latex: latex, display: true));
        }
        i = j + 1;
        continue;
      }
      // Not LaTeX-ish inside — fall through, "[" is just ordinary text.
    }

    // ── Display math: \[ … \] ──
    if (trimmed.startsWith(r'\[')) {
      flushRegion();
      final buf = StringBuffer();
      var j = i;
      var first = true;
      while (j < lines.length) {
        var seg = lines[j];
        if (first) {
          seg = seg.replaceFirst(RegExp(r'^\s*\\\['), '');
          first = false;
        }
        final endIdx = seg.indexOf(r'\]');
        if (endIdx >= 0) {
          buf.write(seg.substring(0, endIdx));
          j++;
          break;
        }
        buf.write(seg);
        buf.write('\n');
        j++;
      }
      blocks.add(PastedMathBlock(latex: buf.toString().trim(), display: true));
      i = j;
      continue;
    }

    // ── Whole-line inline math → math block ──
    final wholeDollar = RegExp(r'^\s*\$(.+)\$\s*$').firstMatch(line);
    if (wholeDollar != null && _isMathish(wholeDollar.group(1)!)) {
      flushRegion();
      blocks.add(PastedMathBlock(latex: wholeDollar.group(1)!.trim(), display: false));
      i++;
      continue;
    }
    final wholeParen = RegExp(r'^\s*\\\((.+)\\\)\s*$').firstMatch(line);
    if (wholeParen != null) {
      flushRegion();
      blocks.add(PastedMathBlock(latex: wholeParen.group(1)!.trim(), display: false));
      i++;
      continue;
    }

    // ── ATX heading → own block ──
    final h = _reHeading.firstMatch(line);
    if (h != null) {
      flushRegion();
      final level = h.group(1)!.length;
      var body = h.group(2)!.replaceAll(RegExp(r'\s*#*\s*$'), '');
      final spans = _tokenize(body, const _Sty(bold: true));
      final block = _finishTextBlock(spans, _headingSizes[level - 1]);
      if (block != null) blocks.add(block);
      i++;
      continue;
    }

    // ── Blank line → paragraph separator ──
    if (trimmed.isEmpty) {
      flushRegion();
      i++;
      continue;
    }

    // ── Ordinary text / list / quote line ──
    addRegionLine(_renderLine(line));
    i++;
  }
  flushRegion();
  return blocks;
}

/// Turn one buffered line into spans, applying list/quote prefixes.
List<TextSpanData> _renderLine(String line) {
  final ul = _reUList.firstMatch(line);
  if (ul != null) {
    final indent = (ul.group(1)!.length / 2).floor();
    final prefix = '${'  ' * indent}• ';
    return [
      TextSpanData(text: prefix),
      ..._tokenize(ul.group(2)!, const _Sty()),
    ];
  }
  final ol = _reOList.firstMatch(line);
  if (ol != null) {
    final indent = (ol.group(1)!.length / 2).floor();
    final prefix = '${'  ' * indent}${ol.group(2)}. ';
    return [
      TextSpanData(text: prefix),
      ..._tokenize(ol.group(3)!, const _Sty()),
    ];
  }
  final q = _reQuote.firstMatch(line);
  if (q != null) {
    return [
      const TextSpanData(text: '> ', italic: true),
      ..._tokenize(q.group(2)!, const _Sty(italic: true)),
    ];
  }
  return _tokenize(line, const _Sty());
}

/// Current inline style while tokenizing.
class _Sty {
  final bool bold, italic, underline, strike, code;
  const _Sty({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
  });
  _Sty copy({bool? bold, bool? italic, bool? underline, bool? strike, bool? code}) =>
      _Sty(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        code: code ?? this.code,
      );
  TextSpanData span(String text) => TextSpanData(
        text: text,
        bold: bold,
        italic: italic,
        underline: underline,
        strikethrough: strike,
        fontFamily: code ? 'monospace' : null,
        color: code ? _codeColor : null,
      );
}

const List<String> _delims = ['***', '___', '**', '__', '~~', '*', '_'];

String? _delimAt(String s, int i) {
  for (final d in _delims) {
    if (s.startsWith(d, i)) {
      final after = i + d.length < s.length ? s[i + d.length] : '';
      if (after == '' || after == ' ' || after == '\t') return null;
      if (d.contains('_')) {
        final before = i > 0 ? s[i - 1] : ' ';
        if (_isAlnum(before)) return null; // intraword underscore → literal
      }
      return d;
    }
  }
  return null;
}

int _findClose(String s, int from, String delim) {
  var i = from;
  while (i <= s.length - delim.length) {
    if (s.startsWith(delim, i)) {
      if (i > 0 && s[i - 1] == r'\') {
        i++;
        continue;
      }
      if (i > from && s[i - 1] != ' ' && s[i - 1] != '\t') {
        if (delim.contains('_')) {
          final after = i + delim.length < s.length ? s[i + delim.length] : ' ';
          if (_isAlnum(after)) {
            i++;
            continue;
          }
        }
        return i;
      }
    }
    i++;
  }
  return -1;
}

_Sty _applyDelim(_Sty cur, String delim) {
  switch (delim) {
    case '***':
    case '___':
      return cur.copy(bold: true, italic: true);
    case '**':
    case '__':
      return cur.copy(bold: true);
    case '~~':
      return cur.copy(strike: true);
    default: // * or _
      return cur.copy(italic: true);
  }
}

int _indexOfUnescaped(String s, String ch, int from) {
  var i = from;
  while (i < s.length) {
    if (s[i] == ch && (i == 0 || s[i - 1] != r'\')) return i;
    i++;
  }
  return -1;
}

List<TextSpanData> _tokenize(String s, _Sty cur) {
  final out = <TextSpanData>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      out.add(cur.span(buf.toString()));
      buf.clear();
    }
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];

    // Inline math \( … \) → unicode (must precede the escape rule, which
    // would otherwise treat "\(" as an escaped paren).
    if (c == r'\' && i + 1 < s.length && s[i + 1] == '(') {
      final close = s.indexOf(r'\)', i + 2);
      if (close >= 0) {
        flush();
        out.add(cur.copy(code: false).span(latexToUnicode(s.substring(i + 2, close))));
        i = close + 2;
        continue;
      }
    }

    // Escape
    if (c == r'\' && i + 1 < s.length && _isMdPunct(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }

    // Inline math → unicode (plain run, keeps forced bold/italic, drops code)
    if (c == r'$') {
      final close = _indexOfUnescaped(s, r'$', i + 1);
      if (close > i + 1 && _isMathish(s.substring(i + 1, close))) {
        flush();
        out.add(cur.copy(code: false).span(latexToUnicode(s.substring(i + 1, close))));
        i = close + 1;
        continue;
      }
      buf.write(c);
      i++;
      continue;
    }

    // Inline code
    if (c == '`') {
      final close = s.indexOf('`', i + 1);
      if (close > i + 1) {
        flush();
        out.add(cur.copy(code: true).span(s.substring(i + 1, close)));
        i = close + 1;
        continue;
      }
      buf.write(c);
      i++;
      continue;
    }

    // Link [text](url) → keep text (underlined), drop url
    if (c == '[') {
      final m = _reLink.matchAsPrefix(s, i);
      if (m != null) {
        flush();
        out.addAll(_tokenize(m.group(1)!, cur.copy(underline: true)));
        i = m.end;
        continue;
      }
      buf.write(c);
      i++;
      continue;
    }

    // Emphasis
    final delim = _delimAt(s, i);
    if (delim != null) {
      final close = _findClose(s, i + delim.length, delim);
      if (close >= 0) {
        flush();
        out.addAll(_tokenize(
            s.substring(i + delim.length, close), _applyDelim(cur, delim)));
        i = close + delim.length;
        continue;
      }
      buf.write(c);
      i++;
      continue;
    }

    buf.write(c);
    i++;
  }
  flush();
  return out;
}

bool _isPlain(TextSpanData s) =>
    !s.bold &&
    !s.italic &&
    !s.underline &&
    !s.strikethrough &&
    s.color == null &&
    s.fontFamily == null;

bool _sameStyle(TextSpanData a, TextSpanData b) =>
    a.bold == b.bold &&
    a.italic == b.italic &&
    a.underline == b.underline &&
    a.strikethrough == b.strikethrough &&
    a.color == b.color &&
    a.fontFamily == b.fontFamily &&
    a.fontSize == b.fontSize;

/// RLE-merge spans, compute content, and collapse to empty spans when the
/// whole block is plain. Returns null when the block is empty.
PastedTextBlock? _finishTextBlock(List<TextSpanData> spans, double fontSize) {
  // Merge adjacent same-style runs.
  final merged = <TextSpanData>[];
  for (final sp in spans) {
    if (sp.text.isEmpty) continue;
    if (merged.isNotEmpty && _sameStyle(merged.last, sp)) {
      merged[merged.length - 1] =
          merged.last.copyWith(text: merged.last.text + sp.text);
    } else {
      merged.add(sp);
    }
  }
  if (merged.isEmpty) return null;
  final content = merged.map((s) => s.text).join();
  if (content.trim().isEmpty) return null;
  final allPlain = merged.every(_isPlain);
  return PastedTextBlock(
    content: content,
    spans: allPlain ? const [] : merged,
    fontSize: fontSize,
  );
}

// ═══════════════════════ LaTeX → Unicode ═══════════════════════

const Map<String, String> _texLetterCmds = {
  // Greek lower
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\epsilon': 'ε', r'\varepsilon': 'ε', r'\zeta': 'ζ', r'\eta': 'η',
  r'\theta': 'θ', r'\vartheta': 'ϑ', r'\iota': 'ι', r'\kappa': 'κ',
  r'\lambda': 'λ', r'\mu': 'μ', r'\nu': 'ν', r'\xi': 'ξ', r'\omicron': 'ο',
  r'\pi': 'π', r'\varpi': 'ϖ', r'\rho': 'ρ', r'\varrho': 'ϱ', r'\sigma': 'σ',
  r'\varsigma': 'ς', r'\tau': 'τ', r'\upsilon': 'υ', r'\phi': 'φ',
  r'\varphi': 'ϕ', r'\chi': 'χ', r'\psi': 'ψ', r'\omega': 'ω',
  // Greek upper
  r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
  r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Upsilon': 'Υ', r'\Phi': 'Φ',
  r'\Psi': 'Ψ', r'\Omega': 'Ω',
  // Operators / relations
  r'\times': '×', r'\cdot': '⋅', r'\div': '÷', r'\pm': '±', r'\mp': '∓',
  r'\leq': '≤', r'\le': '≤', r'\geq': '≥', r'\ge': '≥', r'\neq': '≠',
  r'\ne': '≠', r'\approx': '≈', r'\equiv': '≡', r'\sim': '∼', r'\cong': '≅',
  r'\propto': '∝', r'\infty': '∞', r'\sum': '∑', r'\prod': '∏', r'\int': '∫',
  r'\oint': '∮', r'\partial': '∂', r'\nabla': '∇', r'\in': '∈',
  r'\notin': '∉', r'\ni': '∋', r'\subseteq': '⊆', r'\subset': '⊂',
  r'\supseteq': '⊇', r'\supset': '⊃', r'\cup': '∪', r'\cap': '∩',
  r'\emptyset': '∅', r'\varnothing': '∅', r'\forall': '∀', r'\exists': '∃',
  r'\nexists': '∄', r'\neg': '¬', r'\lnot': '¬', r'\land': '∧',
  r'\wedge': '∧', r'\lor': '∨', r'\vee': '∨', r'\therefore': '∴',
  r'\because': '∵', r'\Rightarrow': '⇒', r'\implies': '⇒', r'\Leftarrow': '⇐',
  r'\Leftrightarrow': '⇔', r'\iff': '⇔', r'\leftrightarrow': '↔',
  r'\rightarrow': '→', r'\to': '→', r'\leftarrow': '←', r'\gets': '←',
  r'\mapsto': '↦', r'\ldots': '…', r'\dots': '…', r'\cdots': '⋯',
  r'\deg': '°', r'\prime': '′', r'\oplus': '⊕', r'\otimes': '⊗',
  r'\angle': '∠', r'\parallel': '∥', r'\perp': '⊥', r'\lfloor': '⌊',
  r'\rfloor': '⌋', r'\lceil': '⌈', r'\rceil': '⌉', r'\quad': '  ',
  r'\qquad': '    ', r'\left': '', r'\right': '',
};

const Map<String, String> _texMathbb = {
  r'\mathbb{R}': 'ℝ', r'\mathbb{N}': 'ℕ', r'\mathbb{Z}': 'ℤ',
  r'\mathbb{Q}': 'ℚ', r'\mathbb{C}': 'ℂ',
};

const Map<String, String> _texPunctCmds = {
  r'\,': ' ', r'\;': ' ', r'\:': ' ', r'\!': '', r'\%': '%', r'\&': '&',
  r'\$': r'$', r'\#': '#', r'\{': '{', r'\}': '}', r'\|': '‖',
};

const Map<String, String> _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶',
  '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽',
  ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ', 'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ',
  'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'j': 'ʲ', 'k': 'ᵏ', 'l': 'ˡ',
  'm': 'ᵐ', 'o': 'ᵒ', 'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
  'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
};

const Map<String, String> _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆',
  '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋', '=': '₌', '(': '₍',
  ')': '₎', 'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ', 'k': 'ₖ',
  'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ',
  't': 'ₜ', 'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ',
};

const Map<String, String> _accents = {
  r'\vec': '⃗', r'\hat': '̂', r'\bar': '̄',
  r'\tilde': '̃', r'\dot': '̇',
};

String _mapScript(String group, Map<String, String> table, String caret,
    {bool single = false}) {
  final sb = StringBuffer();
  var ok = true;
  for (final ch in group.split('')) {
    final m = table[ch];
    if (m == null) {
      ok = false;
      break;
    }
    sb.write(m);
  }
  if (ok) return sb.toString();
  // fallback: keep caret/underscore notation
  return single ? '$caret$group' : '$caret($group)';
}

/// Best-effort LaTeX → Unicode for INLINE math only. Deterministic, total,
/// never throws. Display math is never passed here (it becomes a typeset
/// MathElement).
String latexToUnicode(String input) {
  var tex = input;

  // \sqrt[n]{x} → ⁿ√(x);  \sqrt{x} → √(x);  \sqrt x → √x
  tex = tex.replaceAllMapped(RegExp(r'\\sqrt\[([^\]]*)\]\{([^{}]*)\}'), (m) {
    final idx = _mapScript(m.group(1)!, _superscripts, '^');
    return '$idx√(${m.group(2)})';
  });
  tex = tex.replaceAllMapped(
      RegExp(r'\\sqrt\{([^{}]*)\}'), (m) => '√(${m.group(1)})');
  tex = tex.replaceAllMapped(
      RegExp(r'\\sqrt\s+(\w)'), (m) => '√${m.group(1)}');

  // \frac{a}{b} (innermost first; loop until none remain)
  final fracRe = RegExp(r'\\d?frac\{([^{}]*)\}\{([^{}]*)\}');
  var guard = 0;
  while (fracRe.hasMatch(tex) && guard++ < 32) {
    tex = tex.replaceAllMapped(fracRe, (m) {
      final a = m.group(1)!;
      final b = m.group(2)!;
      if (a.length == 1 && b.length == 1) return '$a⁄$b';
      return '($a)/($b)';
    });
  }

  // Accents \vec{x} etc. (single-char arg → combining mark)
  tex = tex.replaceAllMapped(
      RegExp(r'\\(vec|hat|bar|tilde|dot)\{([^{}]*)\}'), (m) {
    final arg = m.group(2)!;
    final mark = _accents['\\${m.group(1)}'];
    if (arg.length == 1 && mark != null) return '$arg$mark';
    return arg;
  });

  // \mathbb{R} etc. (specific), then generic wrappers keep their arg.
  _texMathbb.forEach((k, v) => tex = tex.replaceAll(k, v));
  tex = tex.replaceAllMapped(
      RegExp(r'\\(text|mathrm|mathbf|mathit|mathbb|operatorname)\{([^{}]*)\}'),
      (m) => m.group(2)!);

  // Letter commands (longest first; boundary so \le doesn't eat \leq).
  final letterKeys = _texLetterCmds.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final letterRe =
      RegExp('(${letterKeys.map(RegExp.escape).join('|')})(?![a-zA-Z])');
  tex = tex.replaceAllMapped(letterRe, (m) => _texLetterCmds[m.group(1)]!);

  // Punctuation/spacing commands (longest first, no boundary).
  final punctKeys = _texPunctCmds.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final punctRe = RegExp(punctKeys.map(RegExp.escape).join('|'));
  tex = tex.replaceAllMapped(punctRe, (m) => _texPunctCmds[m.group(0)]!);

  // Superscripts / subscripts
  tex = tex.replaceAllMapped(RegExp(r'\^\{([^{}]*)\}'),
      (m) => _mapScript(m.group(1)!, _superscripts, '^'));
  tex = tex.replaceAllMapped(RegExp(r'\^(\S)'),
      (m) => _mapScript(m.group(1)!, _superscripts, '^', single: true));
  tex = tex.replaceAllMapped(RegExp(r'_\{([^{}]*)\}'),
      (m) => _mapScript(m.group(1)!, _subscripts, '_'));
  tex = tex.replaceAllMapped(RegExp(r'_(\S)'),
      (m) => _mapScript(m.group(1)!, _subscripts, '_', single: true));

  // Unknown \cmd{arg} → arg;  unknown \cmd → letters; strip stray braces.
  tex = tex.replaceAllMapped(
      RegExp(r'\\[a-zA-Z]+\{([^{}]*)\}'), (m) => m.group(1)!);
  tex = tex.replaceAllMapped(RegExp(r'\\([a-zA-Z]+)'), (m) => m.group(1)!);
  tex = tex.replaceAll('{', '').replaceAll('}', '');

  return tex;
}
