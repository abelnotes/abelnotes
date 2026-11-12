/// Makes delimiters around tall content stretch to its height.
///
/// The training labels write a matrix as `[\begin{matrix}…\end{matrix}]` and
/// the vocabulary has no `\left`/`\right`, so the model can only emit plain
/// brackets, which render at text height next to a multi-row matrix.
library;

const _tall = [r'\begin', r'\frac', r'\sum', r'\int', r'\prod', r'\sqrt'];

String stretchDelimiters(String latex) {
  final tokens = _tokenize(latex);
  final open = <int>[];
  final pairs = <int, int>{};
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == '(' || t == '[' || t == r'\{') {
      if (i > 0 && (tokens[i - 1] == r'\left' || tokens[i - 1] == r'\right')) continue;
      open.add(i);
    } else if (t == ')' || t == ']' || t == r'\}') {
      if (i > 0 && tokens[i - 1] == r'\right') continue;
      if (open.isNotEmpty && _matches(tokens[open.last], t)) pairs[open.removeLast()] = i;
    }
  }
  final left = <int, String>{};
  final right = <int, String>{};
  pairs.forEach((o, c) {
    if (_hasTall(tokens, o + 1, c)) {
      left[o] = r'\left';
      right[c] = r'\right';
    }
  });
  // A brace opening a matrix with no partner is a piecewise definition.
  for (final o in open) {
    if (tokens[o] == r'\{' && o + 1 < tokens.length && tokens[o + 1] == r'\begin') {
      left[o] = r'\left';
      final end = _matrixEnd(tokens, o + 1);
      if (end != null) right[end] = r'\right.';
    }
  }
  // `\right` precedes its closing token; `\right.` follows the `\end{…}`.
  final out = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    if (left[i] != null) out.write(left[i]);
    if (right[i] == r'\right') out.write(r'\right');
    out.write(tokens[i]);
    if (right[i] == r'\right.') out.write(r'\right.');
  }
  return out.toString();
}

bool _matches(String o, String c) =>
    (o == '(' && c == ')') || (o == '[' && c == ']') || (o == r'\{' && c == r'\}');

bool _hasTall(List<String> t, int from, int to) {
  for (var i = from; i < to; i++) {
    if (_tall.contains(t[i])) return true;
  }
  return false;
}

/// Index of the last token of the `\end{…}` closing the environment that
/// starts at [begin], or null.
int? _matrixEnd(List<String> t, int begin) {
  var depth = 0;
  for (var i = begin; i < t.length; i++) {
    if (t[i] == r'\begin') depth++;
    if (t[i] == r'\end') {
      depth--;
      if (depth == 0) {
        var j = i + 1;
        if (j < t.length && t[j] == '{') {
          while (j < t.length && t[j] != '}') {
            j++;
          }
        }
        return j < t.length ? j : t.length - 1;
      }
    }
  }
  return null;
}

/// Splits into commands (`\frac`, `\{`, `\\`), single characters and runs of
/// whitespace, so joining the tokens gives back the input exactly.
List<String> _tokenize(String s) {
  final out = <String>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      var j = i + 1;
      if (_isLetter(s.codeUnitAt(j))) {
        while (j < s.length && _isLetter(s.codeUnitAt(j))) {
          j++;
        }
      } else {
        j++;
      }
      out.add(s.substring(i, j));
      i = j;
    } else {
      out.add(c);
      i++;
    }
  }
  return out;
}

bool _isLetter(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);

/// Closes braces the decoder left open (and drops stray closers), so a
/// near-miss still renders instead of failing to parse. A `\frac` that lost
/// its second argument gets an empty one.
String balanceBraces(String latex) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = 0; i < latex.length; i++) {
    final c = latex[i];
    if (c == r'\' && i + 1 < latex.length) {
      out.write(c);
      out.write(latex[++i]);
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      if (depth == 0) continue;
      depth--;
    }
    out.write(c);
  }
  out.write('}' * depth);
  var s = out.toString();
  // \frac{a} at the very end, or followed by something that isn't a group.
  s = s.replaceAllMapped(RegExp(r'\\frac(\{(?:[^{}]|\{[^{}]*\})*\})(?!\{)'), (m) => '\\frac${m[1]}{}');
  return s;
}
