import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/features/canvas/data/text_paragraph_factory.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:uuid/uuid.dart';

/// One future notebook page produced by the paginator: elements plus the
/// asset keys they reference. Page ids/numbers/filenames are assigned later
/// by the assembler.
class DraftPage {
  final List<ContentElement> elements = [];
  final Set<String> assetRefs = {};
}

/// Flows [ImportBlock]s onto successive A4 pages.
///
/// MUST run on the main isolate: it measures text with the exact
/// [buildTextParagraph] the canvas paints with (font registration is only
/// guaranteed on the root isolate), which is what makes the computed page
/// breaks WYSIWYG. Yields to the event loop every [_yieldEvery] blocks so a
/// large vault doesn't freeze the UI.
class BlockPaginator {
  static const double pageW = AppConfig.defaultPageWidth; // 595
  static const double pageH = AppConfig.defaultPageHeight; // 842
  static const double margin = 48.0;
  static const double contentX = margin;
  static const double contentW = pageW - margin * 2; // 499
  static const double topY = margin;
  static const double bottomY = pageH - margin; // 794
  static const double indentStep = 20.0;
  static const int _yieldEvery = 25;

  /// Text is split across pages only if at least this many lines fit.
  static const int _minSplitLines = 3;

  final _uuid = const Uuid();
  int _zIndex = 0;

  Future<List<DraftPage>> paginate(
    List<ImportBlock> blocks, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final pages = <DraftPage>[DraftPage()];
    var cursorY = topY;

    // Widow control: the last placed heading, if it is still the bottom-most
    // element of the current page (so it can be pulled onto the next page
    // together with the content it introduces).
    ({DraftPage page, ContentElement element, TextBlock block})? danglingHeading;

    void newPage() {
      pages.add(DraftPage());
      cursorY = topY;
    }

    DraftPage page() => pages.last;

    for (var i = 0; i < blocks.length; i++) {
      if (isCancelled?.call() ?? false) return pages;
      if (i % _yieldEvery == 0) {
        onProgress?.call(i, blocks.length);
        await Future<void>.delayed(Duration.zero);
      }
      final block = blocks[i];

      // On a page break, relocate a heading orphaned at the previous page's
      // bottom so it opens the new page instead.
      void breakPage() {
        final dangling = danglingHeading;
        newPage();
        if (dangling != null && dangling.page == pages[pages.length - 2]) {
          dangling.page.elements.remove(dangling.element);
          final h = _placeTextBlock(dangling.block, page(), cursorY);
          cursorY = h.nextY;
        }
        danglingHeading = null;
      }

      switch (block) {
        case TextBlock():
          final style = _styleFor(block.kind);
          cursorY += _spacingBefore(block.kind, atTop: cursorY <= topY);
          final indent = block.indentLevel * indentStep;
          final width = contentW - indent - (block.kind == BlockKind.quote ? 14 : 0);
          final measured = buildTextParagraph(
              _textDataFor(block, style, 0, 0, width),
              width: width);
          final h = measured.height;

          if (cursorY + h + style.extraBoxPad * 2 <= bottomY) {
            final placed = _placeTextBlock(block, page(), cursorY);
            danglingHeading = _isHeading(block.kind)
                ? (page: page(), element: placed.textElement, block: block)
                : null;
            cursorY = placed.nextY;
          } else if (h + style.extraBoxPad * 2 <= bottomY - topY) {
            breakPage();
            final placed = _placeTextBlock(block, page(), cursorY);
            danglingHeading = _isHeading(block.kind)
                ? (page: page(), element: placed.textElement, block: block)
                : null;
            cursorY = placed.nextY;
          } else {
            // Taller than a whole page: split by line metrics.
            danglingHeading = null;
            var rest = block;
            while (true) {
              final available = bottomY - cursorY;
              final para = buildTextParagraph(
                  _textDataFor(rest, style, 0, 0, width),
                  width: width);
              if (para.height <= available) {
                cursorY = _placeTextBlock(rest, page(), cursorY).nextY;
                break;
              }
              final lines = para.computeLineMetrics();
              if (lines.isEmpty) {
                // Defensive: nothing to split by, place whole rest.
                cursorY = _placeTextBlock(rest, page(), cursorY).nextY;
                break;
              }
              var fit = 0;
              var used = 0.0;
              for (final lm in lines) {
                if (used + lm.height > available) break;
                used += lm.height;
                fit++;
              }
              if (fit < _minSplitLines && cursorY > topY) {
                breakPage();
                continue;
              }
              if (fit == 0) fit = 1; // single line taller than a page: force
              final lastLine = lines[fit - 1];
              final charOffset = para
                  .getPositionForOffset(
                      Offset(width, lastLine.baseline - lastLine.ascent / 2))
                  .offset;
              final endOfLine =
                  para.getLineBoundary(TextPosition(offset: charOffset)).end;
              if (endOfLine <= 0 || endOfLine >= rest.plain.length) {
                // Defensive: no progress possible, place whole rest.
                cursorY = _placeTextBlock(rest, page(), cursorY).nextY;
                break;
              }
              final (head, tail) = _splitBlockAt(rest, endOfLine);
              _placeTextBlock(head, page(), cursorY);
              breakPage();
              rest = tail;
            }
          }
          cursorY += _spacingAfter(block.kind);

        case ImageBlock():
          var w = math.min(contentW, block.pxW * 72.0 / 96.0);
          var h = w * block.pxH / math.max(1, block.pxW);
          const usable = bottomY - topY;
          if (h > usable) {
            w *= usable / h;
            h = usable;
          }
          if (cursorY + h > bottomY) breakPage();
          final x = contentX + (contentW - w) / 2;
          page().elements.add(ContentElement.image(
                id: _uuid.v4(),
                zIndex: _zIndex++,
                data: ImageData(
                  x: x,
                  y: cursorY,
                  width: w,
                  height: h,
                  assetPath: block.assetKey,
                ),
              ));
          page().assetRefs.add(block.assetKey);
          danglingHeading = null;
          cursorY += h + 12;

        case DividerBlock():
          if (cursorY + 20 > bottomY) breakPage();
          page().elements.add(ContentElement.shape(
                id: _uuid.v4(),
                zIndex: _zIndex++,
                data: ShapeData(
                  shapeType: 'line',
                  x1: contentX,
                  y1: cursorY + 10,
                  x2: contentX + contentW,
                  y2: cursorY + 10,
                  strokeColor: 0xFFBDBDBD,
                  strokeWidth: 1,
                ),
              ));
          danglingHeading = null;
          cursorY += 20;

        case TableBlock():
          // v1: column-padded monospace grid, then flow it like code text.
          final text = _tableToMonospace(block.rows);
          blocks.insert(
              i + 1,
              TextBlock(
                spans: [TextSpanData(text: text, fontFamily: 'monospace')],
                plain: text,
                kind: BlockKind.code,
              ));

        case MathBlock():
          final size = await _measureMath(block.latex);
          var w = size.width;
          var h = size.height;
          if (w > contentW) {
            h *= contentW / w;
            w = contentW;
          }
          if (cursorY + h > bottomY && cursorY > topY) breakPage();
          page().elements.add(ContentElement.math(
                id: _uuid.v4(),
                zIndex: _zIndex++,
                data: MathData(
                  x: contentX,
                  y: cursorY,
                  width: w,
                  height: h,
                  latex: block.latex,
                ),
              ));
          danglingHeading = null;
          cursorY += h + 12;
      }
    }
    onProgress?.call(blocks.length, blocks.length);

    // Drop a trailing empty page (can happen after a final page break).
    if (pages.length > 1 && pages.last.elements.isEmpty) pages.removeLast();
    return pages;
  }

  // ── text placement ──

  ({double nextY, ContentElement textElement}) _placeTextBlock(
      TextBlock block, DraftPage page, double y) {
    final style = _styleFor(block.kind);
    final indent = block.indentLevel * indentStep;
    final isQuote = block.kind == BlockKind.quote;
    final x = contentX + indent + (isQuote ? 14 : 0);
    final width = contentW - indent - (isQuote ? 14 : 0);
    final textData = _textDataFor(block, style, x, y + style.extraBoxPad, width);
    final para = buildTextParagraph(textData, width: width);
    final h = para.height;
    final sized = textData.copyWith(height: h);

    if (block.kind == BlockKind.code) {
      // Light background card behind the code block, below it in z-order.
      page.elements.add(ContentElement.shape(
            id: _uuid.v4(),
            zIndex: _zIndex++,
            data: ShapeData(
              shapeType: 'rectangle',
              x1: x - 6,
              y1: y,
              x2: x + width + 6,
              y2: y + h + style.extraBoxPad * 2,
              strokeColor: 0xFFE0E0E0,
              strokeWidth: 1,
              fillColor: 0xFFF5F5F5,
            ),
          ));
    } else if (isQuote) {
      page.elements.add(ContentElement.shape(
            id: _uuid.v4(),
            zIndex: _zIndex++,
            data: ShapeData(
              shapeType: 'line',
              x1: contentX + indent + 4,
              y1: y,
              x2: contentX + indent + 4,
              y2: y + h,
              strokeColor: 0xFF9E9E9E,
              strokeWidth: 3,
            ),
          ));
    }

    final el = ContentElement.text(
      id: _uuid.v4(),
      zIndex: _zIndex++,
      data: sized,
    );
    page.elements.add(el);
    return (nextY: y + h + style.extraBoxPad * 2, textElement: el);
  }

  TextData _textDataFor(
      TextBlock block, _KindStyle style, double x, double y, double width) {
    return TextData(
      x: x,
      y: y,
      width: width,
      height: 0,
      content: block.plain,
      fontSize: style.fontSize,
      bold: style.bold,
      italic: block.kind == BlockKind.quote,
      fontFamily:
          block.kind == BlockKind.code ? 'monospace' : 'sans-serif',
      color: block.kind == BlockKind.quote ? 0xFF616161 : 0xFF000000,
      spans: block.spans,
    );
  }

  (TextBlock, TextBlock) _splitBlockAt(TextBlock block, int offset) {
    final headSpans = <TextSpanData>[];
    final tailSpans = <TextSpanData>[];
    var consumed = 0;
    for (final s in block.spans) {
      final end = consumed + s.text.length;
      if (end <= offset) {
        headSpans.add(s);
      } else if (consumed >= offset) {
        tailSpans.add(s);
      } else {
        headSpans.add(s.copyWith(text: s.text.substring(0, offset - consumed)));
        tailSpans.add(s.copyWith(text: s.text.substring(offset - consumed)));
      }
      consumed = end;
    }
    // Trim the leading line break the split leaves behind, keeping the
    // concat(spans)==plain invariant per fragment.
    if (tailSpans.isNotEmpty && tailSpans.first.text.startsWith('\n')) {
      tailSpans[0] =
          tailSpans.first.copyWith(text: tailSpans.first.text.substring(1));
      if (tailSpans.first.text.isEmpty) tailSpans.removeAt(0);
    }
    TextBlock mk(List<TextSpanData> spans) => TextBlock(
          spans: spans,
          plain: spans.map((s) => s.text).join(),
          kind: block.kind,
          indentLevel: block.indentLevel,
        );
    return (mk(headSpans), mk(tailSpans));
  }

  // ── styling / spacing per kind ──

  bool _isHeading(BlockKind kind) =>
      kind.index >= BlockKind.heading1.index &&
      kind.index <= BlockKind.heading6.index;

  _KindStyle _styleFor(BlockKind kind) => switch (kind) {
        BlockKind.heading1 => const _KindStyle(fontSize: 28, bold: true),
        BlockKind.heading2 => const _KindStyle(fontSize: 24, bold: true),
        BlockKind.heading3 => const _KindStyle(fontSize: 20, bold: true),
        BlockKind.heading4 => const _KindStyle(fontSize: 18, bold: true),
        BlockKind.heading5 ||
        BlockKind.heading6 =>
          const _KindStyle(fontSize: 16, bold: true),
        BlockKind.code => const _KindStyle(fontSize: 13, extraBoxPad: 6),
        _ => const _KindStyle(fontSize: 16),
      };

  double _spacingBefore(BlockKind kind, {required bool atTop}) {
    if (atTop) return 0;
    if (_isHeading(kind)) return 18;
    if (kind == BlockKind.code) return 8;
    return 0;
  }

  double _spacingAfter(BlockKind kind) {
    if (_isHeading(kind)) return 12;
    return switch (kind) {
      BlockKind.bullet || BlockKind.ordered || BlockKind.task => 4,
      BlockKind.code => 12,
      _ => 10,
    };
  }

  String _tableToMonospace(List<List<String>> rows) {
    final cols = rows.fold<int>(0, (m, r) => math.max(m, r.length));
    final widths = List<int>.filled(cols, 0);
    for (final r in rows) {
      for (var c = 0; c < r.length; c++) {
        widths[c] = math.max(widths[c], r[c].length);
      }
    }
    final sb = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      sb.writeln([
        for (var c = 0; c < cols; c++)
          (c < r.length ? r[c] : '').padRight(widths[c])
      ].join('  '));
      if (i == 0 && rows.length > 1) {
        sb.writeln([for (final w in widths) ''.padRight(w, '─')].join('  '));
      }
    }
    return sb.toString().trimRight();
  }

  Future<Size> _measureMath(String latex) async {
    try {
      final r = await MathRasterizer.rasterize(
        latex: latex,
        color: const Color(0xFF000000),
        fontSize: 24,
        displayMode: true,
        pixelRatio: 1.0,
      );
      if (r != null) {
        final size = r.size;
        r.image.dispose();
        return size;
      }
    } catch (_) {}
    // Estimate: the canvas placeholder/raster path will still render it.
    final lines = '\n'.allMatches(latex).length + 1;
    return Size(contentW, 40.0 * lines);
  }
}

class _KindStyle {
  final double fontSize;
  final bool bold;

  /// Vertical padding added around the text inside decorated blocks (code).
  final double extraBoxPad;

  const _KindStyle(
      {required this.fontSize, this.bold = false, this.extraBoxPad = 0});
}
