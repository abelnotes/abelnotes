// pdf_text_selection.dart
//
// Selection model for the invisible PDF text layer (see [PdfTextLayer]). Holds
// the page's text as a flat, ordered list of "glyphs" in PAGE-LOGICAL points
// and tracks an anchor/focus range over them. It is transform-agnostic: the
// canvas projects [selectedPageRects] to screen space at paint time, and feeds
// pointer positions back in page space — so zoom/pan never invalidate a
// selection.
//
// A glyph is one character when the run carries per-character boxes, otherwise
// the whole run (so image/OCR-style layers without char boxes still select at
// line granularity). Drag extends a range; a tap (no drag) selects the whole
// run/line under the finger.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:abelnotes/shared/models/ncnote_format.dart';

class _Glyph {
  const _Glyph(this.runIndex, this.text, this.rect);
  final int runIndex;
  final String text; // one char, or the whole run's text when no char boxes
  final Rect rect; // page-logical points
}

class PdfTextSelectionController extends ChangeNotifier {
  PdfTextSelectionController(this.layer) {
    _build();
  }

  final PdfTextLayer layer;

  final List<_Glyph> _glyphs = [];
  // First/last glyph index for each run (inclusive), for tap-to-select-line.
  final List<int> _runFirst = [];
  final List<int> _runLast = [];

  int? _anchor;
  int? _focus;
  bool _dragMoved = false;

  void _build() {
    _runFirst
      ..clear()
      ..addAll(List.filled(layer.runs.length, -1));
    _runLast
      ..clear()
      ..addAll(List.filled(layer.runs.length, -1));
    for (var r = 0; r < layer.runs.length; r++) {
      final run = layer.runs[r];
      _runFirst[r] = _glyphs.length;
      if (run.chars.length == run.text.length && run.chars.isNotEmpty) {
        for (var i = 0; i < run.chars.length; i++) {
          final c = run.chars[i];
          _glyphs.add(_Glyph(
              r, run.text[i], Rect.fromLTWH(c.x, c.y, c.width, c.height)));
        }
      } else {
        _glyphs.add(_Glyph(
            r, run.text, Rect.fromLTWH(run.x, run.y, run.width, run.height)));
      }
      _runLast[r] = _glyphs.length - 1;
    }
  }

  bool get isEmpty => _glyphs.isEmpty;
  bool get hasSelection => _anchor != null && _focus != null;

  /// True if [p] (page-logical points) lands on a glyph — used to decide
  /// whether a mouse drag should select text instead of doing its normal
  /// action. A small margin makes thin glyphs / line gaps forgiving.
  bool isOverText(Offset p, {double margin = 2.5}) {
    for (final g in _glyphs) {
      if (g.rect.inflate(margin).contains(p)) return true;
    }
    return false;
  }

  /// Begin a selection at [pagePos] (page-logical points).
  void begin(Offset pagePos) {
    final i = _nearestGlyph(pagePos);
    if (i < 0) {
      clear();
      return;
    }
    _anchor = i;
    _focus = i;
    _dragMoved = false;
    notifyListeners();
  }

  /// Extend the in-progress selection to [pagePos].
  void update(Offset pagePos) {
    if (_anchor == null) return;
    final i = _nearestGlyph(pagePos);
    if (i < 0) return;
    if (i != _focus) {
      _focus = i;
      if (i != _anchor) _dragMoved = true;
      notifyListeners();
    }
  }

  /// Finish the gesture. A tap (no drag) promotes the selection to the whole
  /// run/line under the anchor.
  void end() {
    if (_anchor != null && !_dragMoved) {
      final run = _glyphs[_anchor!].runIndex;
      _anchor = _runFirst[run];
      _focus = _runLast[run];
      notifyListeners();
    }
  }

  void clear() {
    if (_anchor != null || _focus != null) {
      _anchor = null;
      _focus = null;
      _dragMoved = false;
      notifyListeners();
    }
  }

  (int, int)? get _range {
    if (_anchor == null || _focus == null) return null;
    return (math.min(_anchor!, _focus!), math.max(_anchor!, _focus!));
  }

  /// Bounding rectangles of the selected glyphs, in page-logical points.
  List<Rect> selectedPageRects() {
    final r = _range;
    if (r == null) return const [];
    final out = <Rect>[];
    for (var i = r.$1; i <= r.$2; i++) {
      out.add(_glyphs[i].rect);
    }
    return out;
  }

  /// Union of the selected rects (page-logical points), or null if none.
  Rect? selectionBoundsPage() {
    final rects = selectedPageRects();
    if (rects.isEmpty) return null;
    var b = rects.first;
    for (final r in rects.skip(1)) {
      b = b.expandToInclude(r);
    }
    return b;
  }

  /// The selected text, joining across runs with a space (same line) or a
  /// newline (different line).
  String selectedText() {
    final r = _range;
    if (r == null) return '';
    final sb = StringBuffer();
    int? prevRun;
    for (var i = r.$1; i <= r.$2; i++) {
      final g = _glyphs[i];
      if (prevRun != null && g.runIndex != prevRun) {
        sb.write(_separatorBetweenRuns(prevRun, g.runIndex));
      }
      sb.write(g.text);
      prevRun = g.runIndex;
    }
    return sb.toString();
  }

  String _separatorBetweenRuns(int a, int b) {
    final ra = layer.runs[a];
    final rb = layer.runs[b];
    final lineH = math.max(ra.height, rb.height);
    final sameLine = (rb.y - ra.y).abs() <= 0.5 * lineH;
    return sameLine ? ' ' : '\n';
  }

  /// Index of the glyph nearest to [p] (page-logical). Prefers a glyph that
  /// contains the point; otherwise the closest on the nearest text line.
  /// Returns -1 only when there are no glyphs.
  int _nearestGlyph(Offset p) {
    if (_glyphs.isEmpty) return -1;
    var best = -1;
    var bestScore = double.infinity;
    for (var i = 0; i < _glyphs.length; i++) {
      final r = _glyphs[i].rect;
      final dy = math.max(0.0, math.max(r.top - p.dy, p.dy - r.bottom));
      final dx = math.max(0.0, math.max(r.left - p.dx, p.dx - r.right));
      // Heavily prioritise vertical proximity so selection tracks the line the
      // finger is on, then horizontal distance within that line.
      final score = dy * 1000.0 + dx;
      if (score < bestScore) {
        bestScore = score;
        best = i;
        if (score == 0) break; // inside a glyph — can't do better
      }
    }
    return best;
  }
}
