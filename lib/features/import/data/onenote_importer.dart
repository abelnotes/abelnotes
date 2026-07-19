import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/features/canvas/data/text_paragraph_factory.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/onenote_ffi.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// A parsed OneNote file, ready for [ImportService.registerNotebook]:
/// OneNote pages are freeform, so — unlike the Markdown sources — they skip
/// the A4 paginator and become infinite-canvas pages with elements at their
/// original absolute positions.
class OneNoteParsed {
  final String title;
  final List<OneNoteChapter> chapters;
  final Map<String, Uint8List> assets;
  final List<ImportIssue> issues;

  const OneNoteParsed({
    required this.title,
    required this.chapters,
    required this.assets,
    required this.issues,
  });
}

class OneNoteChapter {
  final String title;
  final List<OneNotePageDraft> pages;

  const OneNoteChapter({required this.title, required this.pages});
}

class OneNotePageDraft {
  final String? title;
  final List<ContentElement> elements;
  final Set<String> assetRefs;

  const OneNotePageDraft({
    required this.title,
    required this.elements,
    required this.assetRefs,
  });
}

/// Maps the JSON tree produced by the Rust bridge (see
/// native/onenote_bridge/src/lib.rs — all coordinates already in points)
/// onto ncnote elements. Sections become chapters, pages become
/// infinite-canvas pages.
class OneNoteImporter {
  /// OneNote's default text size when a run/paragraph specifies none.
  static const double _defaultFontSize = 12.0;

  /// Default width for outlines whose layout width is unknown.
  static const double _defaultOutlineWidth = 420.0;

  static const double _indentStep = 20.0;

  /// OneNote-internal hyperlink marker embedded in run text:
  /// `﷟HYPERLINK "url"visible text`.
  static final _hyperlinkMarker =
      RegExp('﷟' r'HYPERLINK "([^"]*)"');

  final _uuid = const Uuid();
  int _zIndex = 0;

  static bool get isSupported => OneNoteBridge.available;

  Future<OneNoteParsed> parse(
    String filePath, {
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(const ImportProgress(phase: ImportPhase.scanning));

    // The bridge call is synchronous CPU+IO work: run it off the UI thread.
    final tree = await Isolate.run(() => OneNoteBridge.parseFile(filePath));
    if (isCancelled?.call() ?? false) {
      return const OneNoteParsed(
          title: '', chapters: [], assets: {}, issues: []);
    }
    return fromTree(
      tree,
      title: p.basenameWithoutExtension(filePath),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// Maps a bridge JSON tree onto drafts. Public so tests can exercise the
  /// mapping without the native library.
  Future<OneNoteParsed> fromTree(
    Map<String, dynamic> tree, {
    required String title,
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final issues = <ImportIssue>[];
    final assets = <String, Uint8List>{};
    final assetKeyByHash = <String, String>{};
    final chapters = <OneNoteChapter>[];

    final sections = (tree['sections'] as List? ?? const []);
    final totalPages = sections.fold<int>(
        0, (n, s) => n + ((s as Map)['pages'] as List? ?? const []).length);
    var pageCounter = 0;

    for (final sectionRaw in sections) {
      final section = sectionRaw as Map<String, dynamic>;
      final sectionName = (section['name'] as String?)?.trim();
      final pages = <OneNotePageDraft>[];
      for (final pageRaw in (section['pages'] as List? ?? const [])) {
        if (isCancelled?.call() ?? false) break;
        final page = pageRaw as Map<String, dynamic>;
        final pageTitle = (page['title'] as String?)?.trim();
        onProgress?.call(ImportProgress(
          phase: ImportPhase.parsing,
          current: pageCounter++,
          total: totalPages,
          detail: pageTitle?.isNotEmpty == true
              ? pageTitle
              : sectionName,
        ));
        pages.add(_buildPage(
          page,
          source: '${sectionName ?? ''} / ${pageTitle ?? 'pagina'}',
          issues: issues,
          assets: assets,
          assetKeyByHash: assetKeyByHash,
        ));
        await Future<void>.delayed(Duration.zero);
      }
      if (pages.isNotEmpty) {
        chapters.add(OneNoteChapter(
          title: sectionName?.isNotEmpty == true
              ? sectionName!
              : 'Sezione ${chapters.length + 1}',
          pages: pages,
        ));
      }
    }

    if (chapters.isEmpty) {
      throw const FormatException('nessuna pagina importabile nel file');
    }

    return OneNoteParsed(
      title: title,
      chapters: chapters,
      assets: assets,
      issues: issues,
    );
  }

  OneNotePageDraft _buildPage(
    Map<String, dynamic> page, {
    required String source,
    required List<ImportIssue> issues,
    required Map<String, Uint8List> assets,
    required Map<String, String> assetKeyByHash,
  }) {
    final elements = <ContentElement>[];
    final assetRefs = <String>{};
    final skipped = (page['skipped'] as num?)?.toInt() ?? 0;
    if (skipped > 0) {
      issues.add(ImportIssue(
        source: source,
        severity: ImportIssueSeverity.info,
        message: '$skipped elementi non supportati saltati',
      ));
    }

    // Page title as a heading at the canvas origin area.
    final title = (page['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) {
      _addText(
        elements,
        x: 36,
        y: 24,
        width: AppConfig.scratchPageSize / 2,
        spans: [TextSpanData(text: title, bold: true, fontSize: 24)],
        baseSize: 24,
      );
    }

    for (final contentRaw in (page['contents'] as List? ?? const [])) {
      final content = contentRaw as Map<String, dynamic>;
      switch (content['type']) {
        case 'outline':
          _buildOutline(content, elements, assetRefs,
              source: source,
              issues: issues,
              assets: assets,
              assetKeyByHash: assetKeyByHash);
        case 'image':
          final el = _imageElement(content,
              x: _d(content['x']),
              y: _d(content['y']),
              assets: assets,
              assetKeyByHash: assetKeyByHash,
              assetRefs: assetRefs);
          if (el != null) elements.add(el);
        case 'ink':
          _buildInk(content, elements);
      }
    }
    return OneNotePageDraft(
        title: title,
        elements: _centerOnScratchPage(elements),
        assetRefs: assetRefs);
  }

  /// The infinite canvas opens centred on the scratch page's midpoint, so
  /// content imported at OneNote's top-left origin would be off-screen
  /// (blank page on open). Translate everything so the content bounding box
  /// sits around the page centre.
  List<ContentElement> _centerOnScratchPage(List<ContentElement> elements) {
    if (elements.isEmpty) return elements;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void grow(double x0, double y0, double x1, double y1) {
      minX = math.min(minX, x0);
      minY = math.min(minY, y0);
      maxX = math.max(maxX, x1);
      maxY = math.max(maxY, y1);
    }

    for (final el in elements) {
      el.map(
        text: (t) => grow(t.data.x, t.data.y, t.data.x + t.data.width,
            t.data.y + t.data.height),
        image: (i) => grow(i.data.x, i.data.y, i.data.x + i.data.width,
            i.data.y + i.data.height),
        stroke: (s) {
          for (final p in s.data.points) {
            grow(p.x, p.y, p.x, p.y);
          }
        },
        shape: (s) => grow(math.min(s.data.x1, s.data.x2),
            math.min(s.data.y1, s.data.y2), math.max(s.data.x1, s.data.x2),
            math.max(s.data.y1, s.data.y2)),
        math: (m) => grow(m.data.x, m.data.y, m.data.x + m.data.width,
            m.data.y + m.data.height),
      );
    }
    if (!minX.isFinite) return elements;

    const center = AppConfig.scratchPageSize / 2;
    var dx = center - (minX + maxX) / 2;
    var dy = center - (minY + maxY) / 2;
    // Keep the whole box on the page when possible (top-left priority).
    dx = math.max(dx, 24 - minX);
    dy = math.max(dy, 24 - minY);

    return [
      for (final el in elements)
        el.map(
          text: (t) => t.copyWith(
              data: t.data.copyWith(x: t.data.x + dx, y: t.data.y + dy)),
          image: (i) => i.copyWith(
              data: i.data.copyWith(x: i.data.x + dx, y: i.data.y + dy)),
          stroke: (s) => s.copyWith(
              data: s.data.copyWith(points: [
            for (final p in s.data.points)
              p.copyWith(x: p.x + dx, y: p.y + dy),
          ])),
          shape: (s) => s.copyWith(
              data: s.data.copyWith(
            x1: s.data.x1 + dx,
            y1: s.data.y1 + dy,
            x2: s.data.x2 + dx,
            y2: s.data.y2 + dy,
            vertices: [
              for (var i = 0; i < s.data.vertices.length; i++)
                s.data.vertices[i] + (i.isEven ? dx : dy),
            ],
          )),
          math: (m) => m.copyWith(
              data: m.data.copyWith(x: m.data.x + dx, y: m.data.y + dy)),
        ),
    ];
  }

  void _buildOutline(
    Map<String, dynamic> outline,
    List<ContentElement> elements,
    Set<String> assetRefs, {
    required String source,
    required List<ImportIssue> issues,
    required Map<String, Uint8List> assets,
    required Map<String, String> assetKeyByHash,
  }) {
    final ox = _d(outline['x']);
    final oy = _d(outline['y']);
    // OneNote titles/outlines often sit at y≈0; keep everything below the
    // page title block.
    var cursorY = math.max(oy, 60.0);
    final width = _d(outline['width'],
        fallback: _defaultOutlineWidth);

    for (final elRaw in (outline['elements'] as List? ?? const [])) {
      final el = elRaw as Map<String, dynamic>;
      final level = (el['level'] as num?)?.toInt() ?? 0;
      final indent = level * _indentStep;
      switch (el['kind'] ?? el['type']) {
        case 'text':
          cursorY += _d(el['spaceBefore']);
          final spans = _spansFromRuns(el);
          if (spans.isEmpty) {
            cursorY += _defaultFontSize; // empty paragraph = vertical gap
            break;
          }
          final baseSize = _d(el['baseSize'], fallback: _defaultFontSize);
          cursorY += _addText(
            elements,
            x: ox + indent,
            y: cursorY,
            width: math.max(120, width - indent),
            spans: spans,
            baseSize: baseSize,
            baseBold: el['baseBold'] == true,
            baseItalic: el['baseItalic'] == true,
            baseColor: (el['baseColor'] as num?)?.toInt(),
            align: el['align'] as String? ?? 'left',
          );
          cursorY += _d(el['spaceAfter']) + 4;
        case 'table':
          final rows = [
            for (final r in (el['rows'] as List? ?? const []))
              [for (final c in (r as List)) c.toString()]
          ];
          if (rows.isEmpty) break;
          final text = _tableToMonospace(rows);
          cursorY += _addText(
            elements,
            x: ox + indent,
            y: cursorY,
            width: math.max(120, width - indent),
            spans: [TextSpanData(text: text, fontFamily: 'monospace')],
            baseSize: 12,
            fontFamily: 'monospace',
          );
          cursorY += 8;
        case 'image':
          final el2 = _imageElement(el,
              x: ox + indent,
              y: cursorY,
              assets: assets,
              assetKeyByHash: assetKeyByHash,
              assetRefs: assetRefs);
          if (el2 != null) {
            elements.add(el2);
            cursorY += el2.maybeMap(
                    image: (i) => i.data.height, orElse: () => 0.0) +
                8;
          }
        case 'ink':
          // Outline-embedded ink: strokes carry page-absolute coordinates
          // already (offsets baked in by the bridge when present).
          _buildInk(el, elements);
      }
    }
  }

  /// Adds one TextElement, returns its measured height.
  double _addText(
    List<ContentElement> elements, {
    required double x,
    required double y,
    required double width,
    required List<TextSpanData> spans,
    required double baseSize,
    bool baseBold = false,
    bool baseItalic = false,
    int? baseColor,
    String align = 'left',
    String fontFamily = 'sans-serif',
  }) {
    final content = spans.map((s) => s.text).join();
    var textData = TextData(
      x: x,
      y: y,
      width: width,
      height: 0,
      content: content,
      fontSize: baseSize,
      bold: baseBold,
      italic: baseItalic,
      color: baseColor ?? 0xFF000000,
      alignment: align,
      fontFamily: fontFamily,
      spans: spans,
    );
    final para = buildTextParagraph(textData);
    textData = textData.copyWith(height: para.height);
    elements.add(ContentElement.text(
      id: _uuid.v4(),
      zIndex: _zIndex++,
      data: textData,
    ));
    return para.height;
  }

  List<TextSpanData> _spansFromRuns(Map<String, dynamic> el) {
    final spans = <TextSpanData>[];
    final bullet = el['bullet'] == true;
    var first = true;
    for (final runRaw in (el['runs'] as List? ?? const [])) {
      final run = runRaw as Map<String, dynamic>;
      var text = run['text'] as String? ?? '';
      // Resolve OneNote's internal hyperlink markers to plain visible URLs
      // (the canvas auto-styles URLs and makes them Ctrl+clickable).
      text = text.replaceAllMapped(_hyperlinkMarker, (m) {
        final url = m.group(1) ?? '';
        return url.isEmpty ? '' : '$url ';
      });
      if (text.isEmpty) continue;
      if (first && bullet) {
        text = '•  $text';
      }
      first = false;
      spans.add(TextSpanData(
        text: text,
        bold: run['bold'] == true,
        italic: run['italic'] == true,
        underline: run['underline'] == true,
        strikethrough: run['strike'] == true,
        color: (run['color'] as num?)?.toInt(),
        fontSize: (run['size'] as num?)?.toDouble(),
      ));
    }
    // Trim a trailing newline-only tail (OneNote paragraphs often end in \n).
    while (spans.isNotEmpty && spans.last.text.trim().isEmpty) {
      spans.removeLast();
    }
    return spans;
  }

  ContentElement? _imageElement(
    Map<String, dynamic> image, {
    required double x,
    required double y,
    required Map<String, Uint8List> assets,
    required Map<String, String> assetKeyByHash,
    required Set<String> assetRefs,
  }) {
    final b64 = image['b64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return null;
    }
    final hash = sha1.convert(bytes).toString();
    var key = assetKeyByHash[hash];
    if (key == null) {
      final ext = (image['ext'] as String? ?? '').replaceAll('.', '');
      final name = (image['name'] as String?)?.isNotEmpty == true
          ? image['name'] as String
          : 'onenote.${ext.isEmpty ? 'png' : ext}';
      key = '${_uuid.v4()}_$name';
      assetKeyByHash[hash] = key;
      assets[key] = bytes;
    }
    assetRefs.add(key);
    final w = _d(image['width'], fallback: 300);
    final h = _d(image['height'], fallback: w * 0.75);
    return ContentElement.image(
      id: _uuid.v4(),
      zIndex: _zIndex++,
      data: ImageData(
        x: x,
        y: math.max(y, 0),
        width: w,
        height: h,
        assetPath: key,
      ),
    );
  }

  void _buildInk(Map<String, dynamic> ink, List<ContentElement> elements) {
    for (final strokeRaw in (ink['strokes'] as List? ?? const [])) {
      final stroke = strokeRaw as Map<String, dynamic>;
      final flat = (stroke['points'] as List? ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      if (flat.length < 2) continue;
      final points = <StrokePoint>[
        for (var i = 0; i + 1 < flat.length; i += 2)
          StrokePoint(x: flat[i], y: flat[i + 1]),
      ];
      // Single-point stroke = a pen dot; duplicate the point so the stroke
      // painter has a segment to draw.
      if (points.length == 1) points.add(points.first);
      final opacity =
          ((stroke['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.05, 1.0);
      elements.add(ContentElement.stroke(
        id: _uuid.v4(),
        zIndex: _zIndex++,
        data: StrokeData(
          points: points,
          color: (stroke['color'] as num?)?.toInt() ?? 0xFF000000,
          baseWidth:
              ((stroke['width'] as num?)?.toDouble() ?? 2.0).clamp(0.5, 30.0),
          opacity: opacity,
          isHighlighter: opacity < 0.9,
          toolType: opacity < 0.9 ? 'highlighter' : 'pen',
        ),
      ));
    }
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

  double _d(Object? value, {double fallback = 0}) =>
      (value as num?)?.toDouble() ?? fallback;
}
