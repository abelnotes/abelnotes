import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/onenote_importer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Samsung Notes (.sdocx) import: pen strokes per page plus the typed body
/// text and its pictures, on A4 pages. Format notes: README.md here.
class SamsungNotesImporter {
  /// Target page width in points; Samsung pages are 1080 px wide.
  static const double pageWidth = 595;

  /// Samsung text sizes are in dp; 2.625 (420 dpi) puts the pictures of
  /// the sample note where their stored bounds say.
  static const double _textDensity = 2.625;
  static const double _lineSpacing = 1.3;
  static const _objectReplacement = 0xFFFC;

  final _uuid = const Uuid();
  var _z = 0;

  /// Parses the archive bytes. Throws [ImportException] when the file is not
  /// a readable Samsung Notes note.
  OneNoteParsed parse(Uint8List bytes, {required String fallbackTitle}) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ImportException(ImportErrorCode.zipUnreadable);
    }
    Uint8List? file(String name) {
      final f = zip.findFile(name);
      return f == null ? null : Uint8List.fromList(f.content as List<int>);
    }

    final pageFiles = <String, Uint8List>{
      for (final f in zip.files)
        if (f.isFile && f.name.endsWith('.page') && !f.name.contains('/'))
          f.name.substring(0, f.name.length - 5):
              Uint8List.fromList(f.content as List<int>),
    };
    final note = file('note.note');
    if (pageFiles.isEmpty && note == null) {
      throw const ImportException(ImportErrorCode.nothingImportable);
    }

    final order = _pageOrder(file('pageIdInfo.dat'), pageFiles.keys);
    final media = samsungMediaIndex(file('media/mediaInfo.dat'), file);
    final issues = <ImportIssue>[];
    final assets = <String, Uint8List>{};
    var skipped = 0;

    // Pages are laid out one under the other with a gap; strokes may run
    // past the bottom of the page they were started on.
    var srcW = 1080.0, srcH = 1527.0, gap = 24.0;
    final parsedPages = <_SamsungPage>[];
    for (final id in order) {
      try {
        final p = _readPage(pageFiles[id]!);
        parsedPages.add(p);
        skipped += p.skipped;
      } catch (_) {
        skipped++;
      }
    }
    if (parsedPages.isNotEmpty) {
      srcW = parsedPages.first.width;
      srcH = parsedPages.first.height;
    }
    _NoteBody? body;
    if (note != null) {
      try {
        body = _readNote(note);
        gap = body.pageGap;
      } catch (_) {
        skipped++;
      }
    }

    final s = pageWidth / srcW;
    final stride = srcH + gap;
    final pageHeight = srcH * s;
    final pages = <List<ContentElement>>[
      for (var i = 0; i < math.max(parsedPages.length, 1); i++) [],
    ];
    final refs = <Set<String>>[for (final _ in pages) <String>{}];
    void ensure(int n) {
      while (pages.length <= n) {
        pages.add([]);
        refs.add(<String>{});
      }
    }

    for (var i = 0; i < parsedPages.length; i++) {
      for (final st in parsedPages[i].strokes) {
        for (final run in _splitByPage(st.points, stride)) {
          final target = i + run.page;
          if (target < 0) continue;
          ensure(target);
          pages[target].add(_strokeElement(st, run.points, s));
        }
      }
    }

    if (body != null && body.text.isNotEmpty) {
      skipped += _layoutBody(body, media, s, stride, srcH, (page, el, ref) {
        ensure(page);
        pages[page].add(el);
        if (ref != null) {
          refs[page].add(ref.key);
          assets[ref.key] = ref.value;
        }
      });
    }
    if (skipped > 0) {
      issues.add(ImportIssue(
          source: fallbackTitle,
          code: ImportIssueCode.oneNoteElementsSkipped,
          count: skipped));
    }

    final title = (body?.title.trim().isNotEmpty ?? false)
        ? body!.title.trim()
        : fallbackTitle;
    return OneNoteParsed(
      title: title,
      chapters: [
        OneNoteChapter(title: title, pages: [
          for (var i = 0; i < pages.length; i++)
            OneNotePageDraft(
                title: null, elements: pages[i], assetRefs: refs[i]),
        ]),
      ],
      assets: assets,
      issues: issues,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );
  }

  ContentElement _strokeElement(
      _SamsungStroke st, List<_Pt> pts, double s) {
    final points = [
      for (final p in pts)
        StrokePoint(
            x: p.x * s,
            y: p.y * s,
            pressure: st.pressured ? p.pressure.clamp(0.05, 1.0) : 0.5),
    ];
    if (points.length == 1) points.add(points.first);
    final alpha = (st.color >>> 24) & 0xFF;
    final highlighter = alpha < 0xE6;
    return ContentElement.stroke(
      id: _uuid.v4(),
      zIndex: _z++,
      data: StrokeData(
        points: points,
        color: st.color | 0xFF000000,
        baseWidth: (st.size * s).clamp(0.5, 40.0),
        opacity: highlighter ? 0.35 : 1.0,
        isHighlighter: highlighter,
        toolType: highlighter ? 'highlighter' : 'pen',
      ),
    );
  }

  /// Cuts a stroke where it crosses into another page of the column.
  static List<({int page, List<_Pt> points})> _splitByPage(
      List<_Pt> pts, double stride) {
    final out = <({int page, List<_Pt> points})>[];
    int pageOf(_Pt p) => (p.y / stride).floor();
    var cur = pageOf(pts.first);
    var run = <_Pt>[];
    for (final p in pts) {
      final k = pageOf(p);
      if (k != cur && run.isNotEmpty) {
        // Both halves cross the edge, so neither stops short of it.
        out.add((page: cur, points: _shift([...run, p], cur * stride)));
        run = [run.last];
        cur = k;
      }
      run.add(p);
    }
    out.add((page: cur, points: _shift(run, cur * stride)));
    return out;
  }

  static List<_Pt> _shift(List<_Pt> pts, double dy) => dy == 0
      ? pts
      : [for (final p in pts) _Pt(p.x, p.y - dy, p.pressure)];

  /// Lays the body text out top to bottom, one text box per paragraph, and
  /// places the pictures embedded in it. Returns how many items were dropped.
  int _layoutBody(
    _NoteBody body,
    Map<int, ({String name, Uint8List bytes})> media,
    double s,
    double stride,
    double srcH,
    void Function(int page, ContentElement el, MapEntry<String, Uint8List>? asset)
        emit,
  ) {
    var skipped = 0;
    final objects = {for (final o in body.objects) o.textIndex: o};
    final left = body.marginLeft, right = body.flowWidth - body.marginRight;
    var y = body.marginTop;
    var start = 0;
    final text = body.text;
    while (start <= text.length) {
      var end = text.indexOf('\n', start);
      if (end < 0) end = text.length;
      final line = text.substring(start, end);
      final size = body.fontSizeAt(start) * _textDensity;
      final lineH = size * _lineSpacing;
      final obj = line.length == 1 && line.codeUnitAt(0) == _objectReplacement
          ? objects[start]
          : null;
      if (obj != null) {
        final file = media[obj.mediaId];
        if (file == null) {
          skipped++;
        } else {
          final w = obj.width, h = obj.height;
          var page = (y / stride).floor();
          // A picture never straddles two pages: it starts the next one.
          if (y - page * stride + h > srcH && y - page * stride > body.marginTop) {
            page++;
            y = page * stride + body.marginTop;
          }
          final key = '${_uuid.v4()}_${file.name}';
          emit(
              page,
              ContentElement.image(
                id: _uuid.v4(),
                zIndex: _z++,
                data: ImageData(
                  x: obj.left * s,
                  y: (y - page * stride) * s,
                  width: w * s,
                  height: h * s,
                  assetPath: key,
                ),
              ),
              MapEntry(key, file.bytes));
          y += h;
        }
      } else if (line
          .replaceAll(String.fromCharCode(_objectReplacement), '')
          .trim()
          .isNotEmpty) {
        final page = (y / stride).floor();
        emit(
            page,
            ContentElement.text(
              id: _uuid.v4(),
              zIndex: _z++,
              data: TextData(
                x: left * s,
                y: (y - page * stride) * s,
                width: (right - left) * s,
                height: lineH * s,
                content: line.replaceAll(String.fromCharCode(_objectReplacement), ''),
                fontSize: size * s,
                color: body.colorAt(start),
                bold: body.boldAt(start),
                italic: body.italicAt(start),
              ),
            ),
            null);
        y += lineH;
      } else {
        y += lineH;
      }
      start = end + 1;
    }
    return skipped;
  }

  // ── Archive metadata ──

  static List<String> _pageOrder(Uint8List? info, Iterable<String> present) {
    final listed = <String>[];
    if (info != null) {
      try {
        final r = _Reader(info)..p = 32;
        final n = r.u16();
        for (var i = 0; i < n; i++) {
          listed.add(r.utf16(r.u16()));
          r.p += 32;
        }
      } catch (_) {}
    }
    final have = present.toSet();
    final order = [for (final id in listed) if (have.remove(id)) id];
    return order..addAll(have.toList()..sort());
  }

  // ── Page ──

  _SamsungPage _readPage(Uint8List b) {
    final r = _Reader(b);
    final layerOffset = r.u32();
    r.u32(); // property offset
    r.mask();
    r.mask();
    r.u32(); // orientation
    final width = r.u32().toDouble();
    final height = r.u32().toDouble();
    if (width <= 0 || height <= 0) throw const FormatException('page size');
    final page = _SamsungPage(width, height);
    r.p = layerOffset;
    final layers = r.u16();
    r.u16(); // current layer
    for (var l = 0; l < layers; l++) {
      final headerSize = r.u32();
      r.p += headerSize - 4;
      final count = r.u32();
      for (var i = 0; i < count; i++) {
        _readObject(r, page);
      }
      r.p += 32;
    }
    return page;
  }

  void _readObject(_Reader r, _SamsungPage page) {
    final type = r.u8();
    final children = r.u16();
    final size = r.u32();
    final start = r.p;
    if (size < 32 || start + size > r.b.length) {
      throw const FormatException('object size');
    }
    if (type == 1 || type == 15) {
      try {
        final st = _readStroke(_Reader(r.b, start, start + size - 32));
        if (st != null) page.strokes.add(st);
      } catch (_) {
        page.skipped++;
      }
    } else if (type != 0 && type != 4 && type != 100) {
      page.skipped++;
    }
    r.p = start + size;
    for (var i = 0; i < children; i++) {
      _readObject(r, page);
    }
  }

  _SamsungStroke? _readStroke(_Reader r) {
    final base = _Frame.read(r);
    if (base.kind != 0) throw const FormatException('object base');
    if (!base.props.bit(3)) return null; // invisible
    r.p = base.end;
    final f = _Frame.read(r);
    if (f.kind != 1) throw const FormatException('stroke frame');
    final compressed = f.props.bit(0);
    if (f.props.bit(3)) return null; // eraser stroke
    r.p = f.fixedStart;
    final n = r.u16();
    if (n == 0) return null;
    final pts = <_Pt>[];
    final pressure = <double>[];
    if (compressed) {
      var x = r.f64(), y = r.f64();
      pts.add(_Pt(x, y, 1));
      for (var i = 1; i < n; i++) {
        x += _delta(r.u16(), 32);
        y += _delta(r.u16(), 32);
        pts.add(_Pt(x, y, 1));
      }
      var pr = r.f32();
      pressure.add(pr);
      for (var i = 1; i < n; i++) {
        pr += _delta(r.u16(), 4096);
        pressure.add(pr);
      }
    } else {
      for (var i = 0; i < n; i++) {
        pts.add(_Pt(r.f64(), r.f64(), 1));
      }
      for (var i = 0; i < n; i++) {
        pressure.add(r.f32());
      }
    }
    if (r.p > f.fixedEnd) throw const FormatException('stroke points');
    final stroke = _SamsungStroke([
      for (var i = 0; i < n; i++) _Pt(pts[i].x, pts[i].y, pressure[i]),
    ]);
    stroke.pressured = pressure.any((p) => (p - pressure.first).abs() > 1e-3);
    // Style: flexible fields in bit order (pen name id, settings id, colour, size).
    r.p = f.fixedEnd;
    if (f.fields.bit(0)) r.i32();
    if (f.fields.bit(1)) r.i32();
    if (f.fields.bit(2)) stroke.color = r.u32();
    if (f.fields.bit(3)) stroke.size = r.f32();
    if (!stroke.size.isFinite || stroke.size <= 0) stroke.size = 0.8;
    return stroke;
  }

  static double _delta(int w, double div) =>
      (w & 0x8000) != 0 ? -(w & 0x7FFF) / div : (w & 0x7FFF) / div;

  // ── note.note: title and body text ──

  _NoteBody _readNote(Uint8List b) {
    final r = _Reader(b);
    r.u32(); // flexible data offset
    r.mask();
    r.mask();
    r.u32(); // format version
    r.utf16(r.u16()); // note id
    r.u32(); // revision
    r.i64();
    r.i64();
    final flowWidth = r.u32().toDouble();
    r.u32(); // flow height
    r.u32(); // horizontal padding
    final pageGap = r.u32().toDouble();
    r.u32(); // min format version
    final titleSize = r.u32();
    final titleEnd = r.p + titleSize;
    final title = _textObject(_Reader(b, r.p, titleEnd));
    r.p = titleEnd;
    final bodySize = r.u32();
    final body = _textObject(_Reader(b, r.p, r.p + bodySize));
    return _NoteBody(
      title: title?.text ?? '',
      text: body?.text ?? '',
      spans: body?.spans ?? const [],
      objects: body?.objects ?? const [],
      marginLeft: body?.margins[0] ?? 0,
      marginTop: body?.margins[1] ?? 0,
      marginRight: body?.margins[2] ?? 0,
      flowWidth: flowWidth > 0 ? flowWidth : 1080,
      pageGap: pageGap,
    );
  }

  /// Text box object: base frame, shape-base frame (kind 6), shape frame
  /// (kind 7) whose flexible bit 0 carries the text block.
  _TextCommon? _textObject(_Reader r) {
    final base = _Frame.read(r);
    r.p = base.end;
    while (r.p + 14 <= r.end) {
      final f = _Frame.read(r);
      if (f.kind == 7) {
        if (!f.fields.bit(0)) return null;
        r.p = f.flexStart;
        // Text block: a zero u32 in every sample, then the block size.
        var size = r.u32();
        if (size == 0) size = r.u32();
        return _readTextCommon(_Reader(r.b, r.p, r.p + size));
      }
      r.p = f.end;
    }
    return null;
  }

  _TextCommon _readTextCommon(_Reader r) {
    final text = r.utf16(r.u32());
    final spans = <_Span>[];
    final spanCount = r.u32();
    for (var i = 0; i < spanCount; i++) {
      final at = r.p;
      final size = r.u16();
      final type = r.u32(), start = r.u32(), end = r.u32();
      r.u32(); // interval
      final payload = r.p;
      spans.add(_Span(type, start, end, r.b, payload));
      r.p = at + size + 2;
    }
    final paragraphs = r.u32();
    for (var i = 0; i < paragraphs; i++) {
      r.skip(r.u16());
    }
    final margins = [r.f32(), r.f32(), r.f32(), r.f32()];
    r.u8(); // gravity
    final objects = <_EmbeddedImage>[];
    if (r.end - r.p >= 2) {
      final lines = r.u16();
      r.p += lines * 8;
    }
    if (r.end - r.p >= 8) {
      final flags = r.u32();
      r.u32();
      if (flags & 1 != 0) {
        final count = r.u32();
        for (var i = 0; i < count; i++) {
          final spanStart = r.p;
          final spanSize = r.u32();
          final objectSize = r.u32();
          final type = r.u32();
          final objStart = r.p;
          r.p = objStart + objectSize;
          final textIndex = r.u32();
          if (type == 3) {
            final img =
                _readImage(_Reader(r.b, objStart, objStart + objectSize));
            if (img != null) objects.add(img..textIndex = textIndex);
          }
          r.p = spanStart + 4 + spanSize;
        }
      }
    }
    return _TextCommon(text, spans, objects, margins);
  }

  /// Picture object: base bbox for placement; the media bind id sits in the
  /// image fill of the shape frame (kind 7, flexible bit 5).
  _EmbeddedImage? _readImage(_Reader r) {
    final base = _Frame.read(r);
    r.p = base.fixedStart;
    r.u32(); // format version
    r.skip(r.u16()); // uuid
    r.i64();
    final l = r.f64(), t = r.f64(), rt = r.f64(), b = r.f64();
    r.p = base.end;
    while (r.p + 14 <= r.end) {
      final f = _Frame.read(r);
      if (f.kind == 7) {
        r.p = f.flexStart;
        if (f.fields.bit(0)) r.skip(r.u32());
        if (f.fields.bit(1)) r.u8();
        if (f.fields.bit(2)) r.i32();
        if (f.fields.bit(3)) return null;
        if (f.fields.bit(4)) r.i32();
        if (!f.fields.bit(5)) return null;
        r.u32(); // fill size
        if (r.u8() != 2) return null; // not an image fill
        r.u8(); // fill mode
        final id = r.i32();
        if (id < 0) return null;
        return _EmbeddedImage(id, l, t, rt - l, b - t);
      }
      r.p = f.end;
    }
    return null;
  }
}

/// [compute] entry point: (archive bytes, fallback title).
OneNoteParsed parseSamsungNotes((Uint8List, String) args) =>
    SamsungNotesImporter().parse(args.$1, fallbackTitle: args.$2);

/// Bind id → file under media/, from media/mediaInfo.dat.
Map<int, ({String name, Uint8List bytes})> samsungMediaIndex(
    Uint8List? info, Uint8List? Function(String path) read) {
  final out = <int, ({String name, Uint8List bytes})>{};
  if (info == null) return out;
  try {
    final r = _Reader(info);
    r.u32(); // format version
    final n = r.u16();
    for (var i = 0; i < n; i++) {
      final size = r.u32();
      final next = r.p + size;
      final id = r.u32();
      final name = r.utf16(r.u16());
      final bytes = read('media/$name');
      if (bytes != null && !name.contains('/') && !name.contains('..')) {
        out[id] = (name: name.split('@').last, bytes: bytes);
      }
      r.p = next;
    }
  } catch (_) {}
  return out;
}

class _Pt {
  final double x, y, pressure;
  const _Pt(this.x, this.y, this.pressure);
}

class _SamsungStroke {
  final List<_Pt> points;
  var color = 0xFF000000;
  var size = 0.8;
  var pressured = false;
  _SamsungStroke(this.points);
}

class _SamsungPage {
  final double width, height;
  final strokes = <_SamsungStroke>[];
  var skipped = 0;
  _SamsungPage(this.width, this.height);
}

class _Span {
  final int type, start, end;
  final Uint8List b;
  final int payload;
  const _Span(this.type, this.start, this.end, this.b, this.payload);
  bool covers(int i) => start <= i && i < end;
  int u32() => ByteData.sublistView(b, payload, payload + 4)
      .getUint32(0, Endian.little);
  double f32() => ByteData.sublistView(b, payload, payload + 4)
      .getFloat32(0, Endian.little);
}

class _EmbeddedImage {
  final int mediaId;
  final double left, top, width, height;
  var textIndex = -1;
  _EmbeddedImage(this.mediaId, this.left, this.top, this.width, this.height);
}

class _TextCommon {
  final String text;
  final List<_Span> spans;
  final List<_EmbeddedImage> objects;
  final List<double> margins;
  const _TextCommon(this.text, this.spans, this.objects, this.margins);
}

class _NoteBody {
  final String title, text;
  final List<_Span> spans;
  final List<_EmbeddedImage> objects;
  final double marginLeft, marginTop, marginRight, flowWidth, pageGap;
  const _NoteBody({
    required this.title,
    required this.text,
    required this.spans,
    required this.objects,
    required this.marginLeft,
    required this.marginTop,
    required this.marginRight,
    required this.flowWidth,
    required this.pageGap,
  });

  _Span? _last(int type, int i) {
    _Span? hit;
    for (final s in spans) {
      if (s.type == type && s.covers(i)) hit = s;
    }
    return hit;
  }

  double fontSizeAt(int i) {
    final v = _last(3, i)?.f32() ?? 15;
    return v.isFinite && v > 0 ? v : 15;
  }

  int colorAt(int i) => (_last(1, i)?.u32() ?? 0xFF000000) | 0xFF000000;
  bool boldAt(int i) => (_last(5, i)?.u32() ?? 0) != 0;
  bool italicAt(int i) => (_last(6, i)?.u32() ?? 0) != 0;
}

class _Bits {
  final int v;
  const _Bits(this.v);
  bool bit(int i) => (v >> i) & 1 == 1;
}

/// Frame: u32 total size, u16 kind, u32 header size, property and field
/// masks, fixed bytes up to the header size, flexible bytes after.
class _Frame {
  final int start, kind, fixedStart, fixedEnd, end;
  final _Bits props, fields;
  const _Frame(this.start, this.kind, this.fixedStart, this.fixedEnd,
      this.end, this.props, this.fields);
  int get flexStart => fixedEnd;

  static _Frame read(_Reader r) {
    final start = r.p;
    final total = r.u32();
    final kind = r.u16();
    final header = r.u32();
    final props = r.mask();
    final fields = r.mask();
    if (total < 10 || header > total || start + total > r.end) {
      throw const FormatException('frame');
    }
    return _Frame(start, kind, r.p, start + header, start + total,
        _Bits(props), _Bits(fields));
  }
}

class _Reader {
  final Uint8List b;
  final ByteData d;
  int p;
  final int end;
  _Reader(this.b, [int start = 0, int? end])
      : d = ByteData.sublistView(b),
        p = start,
        end = end ?? b.length;

  /// Skips [n] bytes; use instead of `p += u16()`, which adds to the old p.
  void skip(int n) {
    _need(n);
    p += n;
  }

  void _need(int n) {
    if (p + n > end || p < 0) throw const FormatException('truncated');
  }

  int u8() {
    _need(1);
    return b[p++];
  }

  int u16() {
    _need(2);
    final v = d.getUint16(p, Endian.little);
    p += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = d.getUint32(p, Endian.little);
    p += 4;
    return v;
  }

  int i32() {
    _need(4);
    final v = d.getInt32(p, Endian.little);
    p += 4;
    return v;
  }

  int i64() {
    _need(8);
    final v = d.getInt64(p, Endian.little);
    p += 8;
    return v;
  }

  double f32() {
    _need(4);
    final v = d.getFloat32(p, Endian.little);
    p += 4;
    return v;
  }

  double f64() {
    _need(8);
    final v = d.getFloat64(p, Endian.little);
    p += 8;
    return v;
  }

  /// u8 byte count, then the mask bits (low 32 used).
  int mask() {
    final n = u8();
    _need(n);
    var v = 0;
    for (var i = 0; i < math.min(n, 4); i++) {
      v |= b[p + i] << (8 * i);
    }
    p += n;
    return v;
  }

  String utf16(int units) {
    _need(units * 2);
    final codes = [
      for (var i = 0; i < units; i++) d.getUint16(p + 2 * i, Endian.little),
    ];
    p += units * 2;
    return String.fromCharCodes(codes);
  }
}
