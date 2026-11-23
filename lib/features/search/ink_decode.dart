import 'dart:math' as math;
import 'dart:typed_data';

import 'package:abelnotes/shared/utils/text_fold.dart';

/// Word list for the recognizer's beam search: folded words (a-z) with their
/// log-probabilities (assets/models/handwriting_lexicon.tsv, "word\tlogp").
class InkLexicon {
  InkLexicon._(this._logp, this._sorted);

  final Map<String, double> _logp;
  final List<String> _sorted;

  factory InkLexicon.parse(String tsv) {
    final logp = <String, double>{};
    for (final line in tsv.split('\n')) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final p = double.tryParse(line.substring(tab + 1).trim());
      if (p != null) logp[line.substring(0, tab)] = p;
    }
    return InkLexicon._(logp, logp.keys.toList()..sort());
  }

  int get length => _logp.length;

  double? logpOf(String w) => _logp[w];

  /// Some word starts with [p].
  bool isPrefix(String p) {
    var lo = 0, hi = _sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sorted[mid].compareTo(p) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < _sorted.length && _sorted[lo].startsWith(p);
  }
}

/// Beam search settings (the "decoder" object of handwriting_text.json).
class InkDecoderParams {
  final int beam, topk;
  final double cthr, alpha, beta, oov, delta;
  const InkDecoderParams({
    this.beam = 10,
    this.topk = 4,
    this.cthr = 1e-3,
    this.alpha = 0.3,
    this.beta = 4,
    this.oov = -20,
    this.delta = 3,
  });

  factory InkDecoderParams.fromJson(Map<String, dynamic> j) {
    double d(String k, double v) => (j[k] as num?)?.toDouble() ?? v;
    return InkDecoderParams(
      beam: (j['beam'] as num?)?.toInt() ?? 10,
      topk: (j['topk'] as num?)?.toInt() ?? 4,
      cthr: d('cthr', 1e-3),
      alpha: d('alpha', 0.3),
      beta: d('beta', 4),
      oov: d('oov', -20),
      delta: d('delta', 3),
    );
  }
}

const _neg = -1e30;

double _lae(double a, double b) {
  if (a < b) {
    final t = a;
    a = b;
    b = t;
  }
  return b <= _neg ? a : a + math.log(1 + math.exp(b - a));
}

class _Beam {
  double pb = _neg, pnb = _neg;
  final double lm;
  final String word;
  final bool digit, off;
  final int last;
  final List<int> frames;
  final int order;
  _Beam(this.lm, this.word, this.digit, this.off, this.last, this.frames,
      this.order);
}

/// CTC prefix beam search over [probs] (frames x classes, class 0 = blank)
/// with a soft word lexicon: score = log P + alpha * word log-prob + beta per
/// word, minus delta when a word leaves the lexicon's prefixes. Returns the
/// text and each character's frame.
({String text, List<int> frames}) beamDecode(Float32List probs, int frames,
    int classes, List<String> chars, InkLexicon lex, InkDecoderParams p) {
  // Per class: folded a-z letter, or digit, or else a word boundary.
  final letter = <String>[''];
  final digit = <bool>[false];
  for (final ch in chars) {
    final f = foldForSearch(ch);
    final isLetter =
        f.length == 1 && f.codeUnitAt(0) >= 97 && f.codeUnitAt(0) <= 122;
    letter.add(isLetter ? f : '');
    digit.add(!isLetter && '0123456789²'.contains(ch));
  }
  double wordScore(String w, bool dig) {
    if (dig || w.length < 2) return 0;
    return p.alpha * (lex.logpOf(w) ?? p.oov) + p.beta;
  }

  final thr = math.log(p.cthr);
  var beams = <String, _Beam>{
    '': _Beam(0, '', false, false, 0, const [], 0)..pb = 0
  };
  final row = Float64List(classes);
  final idx = List<int>.generate(classes - 1, (i) => i + 1);
  for (var t = 0; t < frames; t++) {
    for (var c = 0; c < classes; c++) {
      row[c] = math.log(math.max(probs[t * classes + c], 1e-12));
    }
    idx.sort((a, b) => row[b].compareTo(row[a]));
    final cand = [
      for (var k = 0; k < math.min(p.topk, idx.length); k++)
        if (row[idx[k]] > thr) idx[k],
    ];
    final next = <String, _Beam>{};
    _Beam get(String txt, _Beam src, int? c) {
      final have = next[txt];
      if (have != null) return have;
      _Beam s;
      if (c == null) {
        s = _Beam(src.lm, src.word, src.digit, src.off, src.last, src.frames,
            next.length);
      } else {
        var lm = src.lm, word = src.word, dig = src.digit, off = src.off;
        if (letter[c].isNotEmpty) {
          word = word + letter[c];
          if (!dig && !off && word.length >= 2 && !lex.isPrefix(word)) {
            off = true;
            lm -= p.delta;
          }
        } else if (digit[c]) {
          dig = true;
          word = '${word}0';
        } else {
          lm += wordScore(word, dig);
          word = '';
          dig = false;
          off = false;
        }
        s = _Beam(lm, word, dig, off, c, [...src.frames, t], next.length);
      }
      next[txt] = s;
      return s;
    }

    for (final e in beams.entries) {
      final b = e.value;
      final pt = _lae(b.pb, b.pnb);
      final s = get(e.key, b, null);
      s.pb = _lae(s.pb, pt + row[0]);
      if (b.last != 0) s.pnb = _lae(s.pnb, b.pnb + row[b.last]);
      for (final c in cand) {
        final s2 = get(e.key + chars[c - 1], b, c);
        s2.pnb = _lae(s2.pnb, (c == b.last ? b.pb : pt) + row[c]);
      }
    }
    final ranked = next.entries.toList()
      ..sort((a, b) {
        final d = (_lae(b.value.pb, b.value.pnb) + b.value.lm)
            .compareTo(_lae(a.value.pb, a.value.pnb) + a.value.lm);
        return d != 0 ? d : a.value.order.compareTo(b.value.order);
      });
    beams = {for (final e in ranked.take(p.beam)) e.key: e.value};
  }
  var best = '';
  var bestFrames = const <int>[];
  var bs = _neg;
  for (final e in beams.entries) {
    final b = e.value;
    final sc = _lae(b.pb, b.pnb) + b.lm + wordScore(b.word, b.digit);
    if (sc > bs) {
      bs = sc;
      best = e.key;
      bestFrames = b.frames;
    }
  }
  return (text: best, frames: bestFrames);
}
