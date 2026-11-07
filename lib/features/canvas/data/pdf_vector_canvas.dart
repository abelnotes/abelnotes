import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:abelnotes/features/canvas/data/pdf_export.dart';
import 'package:abelnotes/features/canvas/data/text_paragraph_factory.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// A canvas call the vector export can't express. The caller falls back to
/// a raster page.
class VectorUnsupported implements Exception {
  final String what;
  const VectorUnsupported(this.what);
  @override
  String toString() => 'VectorUnsupported($what)';
}

/// A [Path] that remembers its moveTo/lineTo/close, which is all the render
/// engine builds (native paths can't be read back).
class VectorPath implements Path {
  final cmds = <double>[];

  @override
  void moveTo(double x, double y) => cmds..add(0)..add(_r(x))..add(_r(y));

  @override
  void lineTo(double x, double y) => cmds..add(1)..add(_r(x))..add(_r(y));

  @override
  void close() => cmds.add(3);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw VectorUnsupported('Path ${invocation.memberName}');
}

// 0.01 pt is far below what any viewer shows and keeps the stream short.
double _r(double v) => (v * 100).roundToDouble() / 100;

const _k = 0.5522847498; // cubic Bézier handle length for a quarter circle

/// Records what the render engine paints as [PdfVecOp]s in page space.
/// Text paragraphs and images become embedded rasters; everything else
/// stays vector. Call [finish] once painting is done.
class VectorCanvas implements Canvas {
  VectorCanvas({required this.knownBytes, double sx = 1, double sy = 1})
      : _m = [sx, 0, 0, sy, 0, 0];

  /// Original encoded bytes of decoded images, so assets embed as they are
  /// instead of being re-encoded. Must be an identity map.
  final Map<ui.Image, Uint8List> knownBytes;

  /// Raster scale for text paragraphs and images without known bytes.
  static const rasterScale = 4.0;

  List<double> _m; // affine a b c d e f
  final _stack = <List<double>>[];
  final _ops = <Object>[]; // PdfVecOp or _Pending, in paint order

  Future<List<PdfVecOp>> finish() async {
    final out = <PdfVecOp>[];
    for (final o in _ops) {
      out.add(o is _Pending ? await o.resolve() : o as PdfVecOp);
    }
    return out;
  }

  // ── Transform ──

  @override
  void save() => _stack.add(List.of(_m));

  @override
  void restore() {
    if (_stack.isNotEmpty) _m = _stack.removeLast();
  }

  @override
  int getSaveCount() => _stack.length + 1;

  @override
  void translate(double dx, double dy) {
    _m[4] += _m[0] * dx + _m[2] * dy;
    _m[5] += _m[1] * dx + _m[3] * dy;
  }

  @override
  void scale(double sx, [double? sy]) {
    sy ??= sx;
    _m[0] *= sx;
    _m[1] *= sx;
    _m[2] *= sy;
    _m[3] *= sy;
  }

  @override
  void rotate(double radians) {
    final c = math.cos(radians), s = math.sin(radians);
    final a = _m[0], b = _m[1], cc = _m[2], d = _m[3];
    _m[0] = a * c + cc * s;
    _m[1] = b * c + d * s;
    _m[2] = cc * c - a * s;
    _m[3] = d * c - b * s;
  }

  // ── Vector shapes ──

  void _add(List<double> cmds, Paint p, {bool forceStroke = false}) {
    if (p.shader != null ||
        p.maskFilter != null ||
        p.imageFilter != null ||
        p.colorFilter != null) {
      throw const VectorUnsupported('paint effect');
    }
    final bm = p.blendMode;
    if (bm != BlendMode.srcOver && bm != BlendMode.multiply) {
      throw VectorUnsupported('blend $bm');
    }
    final stroke = forceStroke || p.style == PaintingStyle.stroke;
    _ops.add(PdfVecPath(
      m: List.of(_m),
      cmds: cmds,
      color: p.color.toARGB32(),
      strokeWidth: stroke ? p.strokeWidth : null,
      cap: p.strokeCap.index,
      join: p.strokeJoin.index,
      multiply: bm == BlendMode.multiply,
    ));
  }

  @override
  void drawPath(Path path, Paint paint) {
    if (path is! VectorPath) throw const VectorUnsupported('native Path');
    _add(path.cmds, paint);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => _add(
      [0, _r(p1.dx), _r(p1.dy), 1, _r(p2.dx), _r(p2.dy)], paint,
      forceStroke: true);

  @override
  void drawRect(Rect r, Paint paint) => _add([
        0, r.left, r.top, 1, r.right, r.top, //
        1, r.right, r.bottom, 1, r.left, r.bottom, 3,
      ], paint);

  @override
  void drawOval(Rect r, Paint paint) => _add(_oval(r), paint);

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      _add(_oval(Rect.fromCircle(center: c, radius: radius)), paint);

  @override
  void drawRRect(RRect rr, Paint paint) {
    final l = rr.left, t = rr.top, r = rr.right, b = rr.bottom;
    _add([
      0, l + rr.tlRadiusX, t,
      1, r - rr.trRadiusX, t,
      2, r - rr.trRadiusX * (1 - _k), t, r, t + rr.trRadiusY * (1 - _k), r, t + rr.trRadiusY,
      1, r, b - rr.brRadiusY,
      2, r, b - rr.brRadiusY * (1 - _k), r - rr.brRadiusX * (1 - _k), b, r - rr.brRadiusX, b,
      1, l + rr.blRadiusX, b,
      2, l + rr.blRadiusX * (1 - _k), b, l, b - rr.blRadiusY * (1 - _k), l, b - rr.blRadiusY,
      1, l, t + rr.tlRadiusY,
      2, l, t + rr.tlRadiusY * (1 - _k), l + rr.tlRadiusX * (1 - _k), t, l + rr.tlRadiusX, t,
      3,
    ], paint);
  }

  @override
  void drawPoints(PointMode mode, List<Offset> points, Paint paint) {
    final cmds = <double>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = _r(p.dx), y = _r(p.dy);
      switch (mode) {
        case PointMode.points: // zero-length segment: a dot with round caps
          cmds.addAll([0, x, y, 1, x, y]);
        case PointMode.lines:
          cmds.addAll([i.isEven ? 0 : 1, x, y]);
        case PointMode.polygon:
          cmds.addAll([i == 0 ? 0 : 1, x, y]);
      }
    }
    if (cmds.isNotEmpty) _add(cmds, paint, forceStroke: true);
  }

  // ── Rasters ──

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    if (src != Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())) {
      throw const VectorUnsupported('partial image');
    }
    final alpha = paint.color.a;
    final bytes = knownBytes[image];
    if (bytes != null) {
      _ops.add(PdfVecImage(m: List.of(_m), bytes: bytes, x: dst.left, y: dst.top,
          w: dst.width, h: dst.height, alpha: alpha));
    } else {
      _ops.add(_Pending(List.of(_m), dst, alpha, image: image));
    }
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    const pad = 4.0; // italics and descenders can overhang the layout box
    final w = paragraph.width.isFinite ? paragraph.width : paragraph.maxIntrinsicWidth;
    final rect = Rect.fromLTWH(offset.dx - pad, offset.dy - pad,
        w + 2 * pad, paragraph.height + 2 * pad);
    if (rect.isEmpty) return;
    final rec = ui.PictureRecorder();
    Canvas(rec)
      ..scale(rasterScale)
      ..translate(-rect.left, -rect.top)
      ..drawParagraph(paragraph, offset);
    _ops.add(_Pending(List.of(_m), rect, 1, picture: rec.endRecording()));
  }

  /// A text element as real, selectable PDF text, placed per line and
  /// style run where the laid-out [paragraph] put it. Text the standard
  /// fonts can't encode is drawn as an image instead.
  void drawText(TextData t, Paragraph paragraph, Offset offset) {
    final runs = textRuns(t).toList();
    final content = runs.map((r) => r.text).join();
    if (!pdfCanEncode(content)) return drawParagraph(paragraph, offset);
    final lines = paragraph.computeLineMetrics();
    var start = 0;
    for (final r in runs) {
      final end = start + r.text.length;
      final span = r.span;
      final style = (
        size: span?.fontSize ?? t.fontSize,
        color: r.asLink ? 0xFF1565C0 : (span?.color ?? t.color),
        mono: (span?.fontFamily ?? t.fontFamily) == 'monospace',
        bold: (span?.bold ?? false) || t.bold,
        italic: (span?.italic ?? false) || t.italic,
        underline: (span?.underline ?? false) || r.asLink,
        strike: span?.strikethrough ?? false,
      );
      // One piece per laid-out line inside this run.
      for (var i = start; i < end;) {
        final ln = paragraph.getLineNumberAt(i);
        if (content.codeUnitAt(i) == 0x0A || ln == null || ln >= lines.length) {
          i++;
          continue;
        }
        var j = i + 1;
        while (j < end &&
            content.codeUnitAt(j) != 0x0A &&
            paragraph.getLineNumberAt(j) == ln) {
          j++;
        }
        _textPiece(paragraph, content, i, j, offset.dx,
            offset.dy + lines[ln].baseline, style);
        i = j;
      }
      start = end;
    }
  }

  void _textPiece(
      Paragraph p,
      String content,
      int from,
      int to,
      double dx,
      double baseline,
      ({double size, int color, bool mono, bool bold, bool italic,
          bool underline, bool strike}) st) {
    while (to > from && content.codeUnitAt(to - 1) == 0x20) {
      to--; // a wrapped line's trailing space sits past the line end
    }
    if (to <= from) return;
    final boxes = p.getBoxesForRange(from, to);
    if (boxes.isEmpty) return;
    final left = boxes.map((b) => b.left).reduce(math.min);
    final right = boxes.map((b) => b.right).reduce(math.max);
    final text = pdfSafeText(content.substring(from, to));
    final natural = pdfTextWidth(text, st.size,
        mono: st.mono, bold: st.bold, italic: st.italic);
    final x = dx + left, w = right - left;
    _ops.add(PdfVecText(
      m: List.of(_m),
      text: text,
      x: _r(x),
      y: _r(baseline),
      size: st.size,
      // Standard fonts differ a little from the screen font; fit the width.
      hscale: natural > 0 ? (w / natural).clamp(0.5, 2.0) : 1,
      color: st.color,
      mono: st.mono,
      bold: st.bold,
      italic: st.italic,
    ));
    final thick = math.max(st.size / 16, 0.5);
    for (final (on, y) in [
      (st.underline, baseline + st.size * 0.12),
      (st.strike, baseline - st.size * 0.28),
    ]) {
      if (!on) continue;
      _ops.add(PdfVecPath(
          m: List.of(_m),
          cmds: [0, _r(x), _r(y), 1, _r(x + w), _r(y)],
          color: st.color,
          strokeWidth: thick));
    }
  }

  List<double> _oval(Rect r) {
    final cx = r.center.dx, cy = r.center.dy;
    final rx = r.width / 2, ry = r.height / 2;
    return [
      0, cx + rx, cy,
      2, cx + rx, cy + ry * _k, cx + rx * _k, cy + ry, cx, cy + ry,
      2, cx - rx * _k, cy + ry, cx - rx, cy + ry * _k, cx - rx, cy,
      2, cx - rx, cy - ry * _k, cx - rx * _k, cy - ry, cx, cy - ry,
      2, cx + rx * _k, cy - ry, cx + rx, cy - ry * _k, cx + rx, cy,
      3,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw VectorUnsupported('Canvas ${invocation.memberName}');
}

/// An image op whose PNG bytes are encoded after painting (async).
class _Pending {
  _Pending(this.m, this.dst, this.alpha, {this.image, this.picture});
  final List<double> m;
  final Rect dst;
  final double alpha;
  final ui.Image? image;
  final ui.Picture? picture;

  Future<PdfVecImage> resolve() async {
    var img = image;
    if (picture != null) {
      img = await picture!.toImage(
          (dst.width * VectorCanvas.rasterScale).ceil(),
          (dst.height * VectorCanvas.rasterScale).ceil());
      picture!.dispose();
    }
    try {
      final data = await img!.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const VectorUnsupported('image encode');
      return PdfVecImage(m: m, bytes: data.buffer.asUint8List(), x: dst.left,
          y: dst.top, w: dst.width, h: dst.height, alpha: alpha);
    } finally {
      if (picture != null) img!.dispose();
    }
  }
}
