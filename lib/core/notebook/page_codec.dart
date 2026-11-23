// Page codec: compact JSON and the binary ABPG page format.
import 'dart:convert';
import 'dart:typed_data';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Compact JSON encode for a PageData.
///
/// Two reductions applied:
///
/// (1) Doubles rounded to 3 decimals (sub-1‰ — well below visible
///     pixel precision and finer than the tablet's 10-bit ADC).
///
/// (2) StrokePoint objects emitted as compact arrays
///     `[x, y, pressure?, tilt?, timestamp?]` with trailing defaults
///     omitted. A point with pressure=0.5, tilt=0, timestamp=0
///     becomes `[x, y]` (2 elements) instead of a 5-field object.
///     Decoder counter-part is [_expandStrokePointsInPlace] (applied
///     via [decodePageData]) which restores the map form before
///     handing to the generated PageData.fromJson.
///
/// Combined effect on a typical 100-point stroke: JSON drops from
/// ~8-10 KB to ~1.5-2.5 KB (75-85% smaller). Same wire schema for
/// the surrounding tree, both forms accepted on read so old notebooks
/// continue to load unchanged.
///
/// Elements are immutable, so each one's encoding is kept by identity: saving
/// a dense page after one more stroke encodes that stroke, not the page.
String compactPageJson(PageData page) =>
    _spliceContent(page, (e) => _elementJson[e] ??= _compactElementJson(e)) ??
    _compactTreeJson(page.toJson());

/// [page]'s compact JSON with each content element written by [element];
/// null if the page JSON has no place for them (cannot happen in practice).
String? _spliceContent(
    PageData page, String Function(ContentElement) element) {
  final content = page.layers.content;
  final skeleton = _compactTreeJson(
      page.copyWith(layers: page.layers.copyWith(content: const [])).toJson());
  if (content.isEmpty) return skeleton;
  // Cannot occur inside a JSON string: the quote after `content` would be escaped.
  const hole = '"content":[]';
  final at = skeleton.indexOf(hole);
  if (at < 0) return null;
  final out = StringBuffer(skeleton.substring(0, at + hole.length - 1));
  for (var i = 0; i < content.length; i++) {
    if (i > 0) out.write(',');
    out.write(element(content[i]));
  }
  out.write(skeleton.substring(at + hole.length - 1));
  return out.toString();
}

final _elementJson = Expando<String>('compactElementJson');

String _compactTreeJson(Object? raw) {
  final rounded = _roundFloatsInPlace(raw);
  _compactStrokePointsInPlace(rounded);
  return jsonEncode(rounded);
}

String _compactElementJson(ContentElement e) {
  if (e is! StrokeElement) {
    return _compactTreeJson(const ContentListConverter().toJson([e]).single);
  }
  final points = e.data.points;
  final shell = _compactTreeJson(e.copyWith.data(points: const []).toJson());
  const hole = '"points":[]';
  final at = shell.indexOf(hole);
  if (at < 0) return _compactTreeJson(e.toJson());
  final out = StringBuffer(shell.substring(0, at + hole.length - 1));
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    if (!p.x.isFinite || !p.y.isFinite || !p.pressure.isFinite || !p.tilt.isFinite) {
      return _compactTreeJson(e.toJson()); // jsonEncode's own handling
    }
    if (i > 0) out.write(',');
    // Same rounding and default trimming as _pointMapToArray.
    final pr = (p.pressure * 1000).round() / 1000, t = (p.tilt * 1000).round() / 1000;
    out
      ..write('[')
      ..write((p.x * 1000).round() / 1000)
      ..write(',')
      ..write((p.y * 1000).round() / 1000);
    if (p.timestamp != 0 || t != 0.0 || pr != 0.5) out..write(',')..write(pr);
    if (p.timestamp != 0 || t != 0.0) out..write(',')..write(t);
    if (p.timestamp != 0) out..write(',')..write(p.timestamp);
    out.write(']');
  }
  out.write(shell.substring(at + hole.length - 1));
  return out.toString();
}

/// Counterpart to [compactPageJson]: reads both point forms, the compact
/// `[x,y,p,t,ts]` arrays and the older maps. Mutates [json]: stroke points
/// are built here directly, so `PageData.fromJson` never sees one map per
/// point. Always use this instead of `PageData.fromJson` on page JSON.
PageData decodePageData(Map<String, dynamic> json) {
  final layers = json['layers'];
  final content = layers is Map ? layers['content'] : null;
  final points = <int, List<StrokePoint>>{};
  if (content is List) {
    for (var i = 0; i < content.length; i++) {
      final e = content[i];
      if (e is! Map || e['type'] != 'stroke') continue;
      final data = e['data'];
      final pts = data is Map ? data['points'] : null;
      if (pts is List && pts.isNotEmpty) {
        points[i] = _decodeStrokePoints(pts);
        data['points'] = const <dynamic>[];
      }
    }
  }
  return _withPoints(PageData.fromJson(json), points);
}

/// [page] with the strokes at the given content indices given these points.
PageData _withPoints(PageData page, Map<int, List<StrokePoint>> points) {
  if (points.isEmpty) return page;
  // ContentListConverter keeps one element per entry, so indices line up.
  final elements = List<ContentElement>.of(page.layers.content);
  points.forEach((i, pts) {
    final e = elements[i];
    if (e is StrokeElement) elements[i] = e.copyWith.data(points: pts);
  });
  return page.copyWith(layers: page.layers.copyWith(content: elements));
}

// ── Page bytes ──
//
// A page is stored as compact JSON or in a binary form with the same
// content: "ABPG", a version byte, the length and UTF-8 of the page's compact
// JSON with every stroke's points left out, the number of strokes, then each
// stroke's points as zigzag varint deltas of thousandths, the precision the
// JSON keeps. Readers take both; writers use the binary form only once
// [AppConfig.writeBinaryPages] is on. Format notes: ABELNOTE_FORMAT_GUIDE.md.

const _binMagic = [0x41, 0x42, 0x50, 0x47]; // "ABPG"
const _binVersion = 1;

/// A binary page in a format newer than this app reads. Not a
/// [FormatException]: the page is not corrupt, and nothing may overwrite it.
class PageFormatTooNewException implements Exception {
  const PageFormatTooNewException(this.version);
  final int version;
  @override
  String toString() =>
      'PageFormatTooNewException: page format $version is newer than this app reads';
}

/// The bytes a page is stored as, on disk and on the server.
Uint8List encodePageBytes(PageData page) =>
    (AppConfig.writeBinaryPages ? binaryPageBytes(page) : null) ??
    Uint8List.fromList(utf8.encode(compactPageJson(page)));

bool isBinaryPage(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == _binMagic[0] &&
    bytes[1] == _binMagic[1] &&
    bytes[2] == _binMagic[2] &&
    bytes[3] == _binMagic[3];

/// Reads a stored page in either form. A damaged page throws
/// [FormatException], a binary page of a later format
/// [PageFormatTooNewException].
PageData decodePageBytes(List<int> bytes) {
  if (isBinaryPage(bytes)) {
    return _decodeBinaryPage(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }
  return decodePageData(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
}

/// [page] in the binary form; null for a stroke point that is not a finite
/// number, which only the JSON path handles.
Uint8List? binaryPageBytes(PageData page) {
  final blocks = <Uint8List>[];
  for (final e in page.layers.content) {
    if (e is! StrokeElement) continue;
    final block = _pointBlocks[e] ?? _encodePointBlock(e.data.points);
    if (block == null) return null;
    blocks.add(_pointBlocks[e] = block);
  }
  final skeleton = _spliceContent(page, _skeletonElementJson);
  if (skeleton == null) return null;
  final json = utf8.encode(skeleton);
  final w = _ByteWriter()
    ..bytes(_binMagic)
    ..byte(_binVersion)
    ..varint(json.length)
    ..bytes(json)
    ..varint(blocks.length);
  for (final b in blocks) {
    w.bytes(b);
  }
  return w.take();
}

final _pointBlocks = Expando<Uint8List>('binaryPointBlock');
final _skeletonJson = Expando<String>('binaryElementSkeleton');

String _skeletonElementJson(ContentElement e) => e is StrokeElement
    ? (_skeletonJson[e] ??=
        _compactTreeJson(e.copyWith.data(points: const []).toJson()))
    : (_elementJson[e] ??= _compactElementJson(e));

Uint8List? _encodePointBlock(List<StrokePoint> pts) {
  final n = pts.length;
  final xs = List<int>.filled(n, 0), ys = List<int>.filled(n, 0);
  final ps = List<int>.filled(n, 0), ts = List<int>.filled(n, 0);
  final ms = List<int>.filled(n, 0);
  var flags = 0;
  for (var i = 0; i < n; i++) {
    final p = pts[i];
    if (!p.x.isFinite || !p.y.isFinite || !p.pressure.isFinite || !p.tilt.isFinite) {
      return null;
    }
    // Same rounding as compactPageJson, so both forms decode alike.
    xs[i] = (p.x * 1000).round();
    ys[i] = (p.y * 1000).round();
    ps[i] = (p.pressure * 1000).round();
    ts[i] = (p.tilt * 1000).round();
    ms[i] = p.timestamp;
    if (ps[i] != 500) flags |= 1;
    if (ts[i] != 0) flags |= 2;
    if (ms[i] != 0) flags |= 4;
  }
  final w = _ByteWriter()
    ..varint(n)
    ..byte(flags);
  void run(List<int> v) {
    var prev = 0;
    for (final x in v) {
      w.zigzag(x - prev);
      prev = x;
    }
  }

  run(xs);
  run(ys);
  if (flags & 1 != 0) run(ps);
  if (flags & 2 != 0) run(ts);
  if (flags & 4 != 0) run(ms);
  return w.take();
}

PageData _decodeBinaryPage(Uint8List b) {
  final version = b[4];
  if (version > _binVersion) throw PageFormatTooNewException(version);
  if (version != _binVersion) {
    throw const FormatException('binary page: unknown version');
  }
  try {
    final r = _ByteReader(b, 5);
    final length = r.varint();
    final end = r.pos + length;
    if (end > b.length) throw const FormatException('binary page: truncated');
    final json = jsonDecode(utf8.decode(Uint8List.sublistView(b, r.pos, end)))
        as Map<String, dynamic>;
    r.pos = end;
    final count = r.varint();
    final layers = json['layers'];
    final content = layers is Map ? layers['content'] : null;
    final points = <int, List<StrokePoint>>{};
    if (content is List) {
      for (var i = 0; i < content.length; i++) {
        final e = content[i];
        if (e is! Map || e['type'] != 'stroke') continue;
        if (points.length == count) {
          throw const FormatException('binary page: missing points');
        }
        points[i] = _readPointBlock(r);
      }
    }
    if (points.length != count || r.pos != b.length) {
      throw const FormatException('binary page: strokes do not match');
    }
    return _withPoints(PageData.fromJson(json), points);
  } on ArgumentError {
    // Index past the end: a cut-off file.
    throw const FormatException('binary page: truncated');
  }
}

List<StrokePoint> _readPointBlock(_ByteReader r) {
  final n = r.varint();
  final flags = r.byte();
  // Each point takes at least two bytes: a bigger count is damage.
  if (n * 2 > r.b.length - r.pos) {
    throw const FormatException('binary page: bad point count');
  }
  List<int> run() {
    final v = List<int>.filled(n, 0);
    var acc = 0;
    for (var i = 0; i < n; i++) {
      acc += r.zigzag();
      v[i] = acc;
    }
    return v;
  }

  final xs = run(), ys = run();
  final ps = flags & 1 != 0 ? run() : null;
  final ts = flags & 2 != 0 ? run() : null;
  final ms = flags & 4 != 0 ? run() : null;
  return List<StrokePoint>.generate(
    n,
    (i) => StrokePoint(
      x: xs[i] / 1000,
      y: ys[i] / 1000,
      pressure: ps == null ? 0.5 : ps[i] / 1000,
      tilt: ts == null ? 0.0 : ts[i] / 1000,
      timestamp: ms == null ? 0 : ms[i],
    ),
    growable: false,
  );
}

// Varints by arithmetic, not shifts: on the web an int is a double and
// shifts cut it to 32 bits.
class _ByteWriter {
  Uint8List _b = Uint8List(256);
  int _n = 0;

  void _room(int k) {
    if (_n + k <= _b.length) return;
    var size = _b.length * 2;
    while (size < _n + k) {
      size *= 2;
    }
    _b = Uint8List(size)..setRange(0, _n, _b);
  }

  void byte(int v) {
    _room(1);
    _b[_n++] = v;
  }

  void bytes(List<int> v) {
    _room(v.length);
    _b.setRange(_n, _n + v.length, v);
    _n += v.length;
  }

  void varint(int v) {
    _room(10);
    while (v >= 0x80) {
      _b[_n++] = 0x80 + v % 0x80;
      v = v ~/ 0x80;
    }
    _b[_n++] = v;
  }

  void zigzag(int v) => varint(v >= 0 ? v * 2 : -v * 2 - 1);

  Uint8List take() => _b.sublist(0, _n);
}

class _ByteReader {
  _ByteReader(this.b, this.pos);
  final Uint8List b;
  int pos;

  int byte() => b[pos++];

  int varint() {
    var v = 0, scale = 1;
    while (true) {
      final x = b[pos++];
      v += (x % 0x80) * scale;
      if (x < 0x80) return v;
      scale *= 0x80;
      if (scale > 9007199254740992) {
        throw const FormatException('binary page: varint too long');
      }
    }
  }

  int zigzag() {
    final z = varint();
    return z.isEven ? z ~/ 2 : -((z + 1) ~/ 2);
  }
}

/// Same values and defaults as StrokePoint.fromJson on the expanded map.
List<StrokePoint> _decodeStrokePoints(List pts) => [
      for (final p in pts)
        if (p is List)
          StrokePoint(
            x: (p[0] as num).toDouble(),
            y: (p[1] as num).toDouble(),
            pressure: p.length > 2 ? (p[2] as num?)?.toDouble() ?? 0.5 : 0.5,
            tilt: p.length > 3 ? (p[3] as num?)?.toDouble() ?? 0.0 : 0.0,
            timestamp: p.length > 4 ? (p[4] as num?)?.toInt() ?? 0 : 0,
          )
        else
          StrokePoint.fromJson(p as Map<String, dynamic>),
    ];

Object? _roundFloatsInPlace(Object? v) {
  if (v is double) {
    // Arithmetic rounding, NOT double.parse(v.toStringAsFixed(3)): the
    // string round-trip allocates+parses a String per double, and a
    // dense page is ~80k doubles — that was measurable jank on every
    // save since encoding runs on the main thread. The two roundings
    // can differ by 1 ulp on ties, irrelevant at page-coordinate scale.
    return v.isFinite ? (v * 1000).round() / 1000 : v;
  }
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, val) {
      out[k as String] = _roundFloatsInPlace(val);
    });
    return out;
  }
  if (v is List) {
    return v.map(_roundFloatsInPlace).toList(growable: false);
  }
  return v;
}

/// Walk the page JSON tree and replace `points: [{...}, {...}]` lists
/// inside a `stroke` ContentElement with compact `points: [[x,y,..], ..]`.
/// Operates in place on the tree produced by toJson() — only the
/// `points` list under each stroke element is mutated, the rest of
/// the structure (zIndex, id, data wrapper, type) stays intact.
void _compactStrokePointsInPlace(Object? v) {
  if (v is Map) {
    if (v['type'] == 'stroke') {
      final data = v['data'];
      if (data is Map && data['points'] is List) {
        final pts = data['points'] as List;
        for (var i = 0; i < pts.length; i++) {
          final p = pts[i];
          if (p is Map) pts[i] = _pointMapToArray(p);
        }
      }
    }
    v.forEach((_, val) {
      if (val is Map || val is List) _compactStrokePointsInPlace(val);
    });
  } else if (v is List) {
    for (final item in v) { _compactStrokePointsInPlace(item); }
  }
}

List<num> _pointMapToArray(Map p) {
  final x = p['x'] as num;
  final y = p['y'] as num;
  final pr = (p['pressure'] as num?) ?? 0.5;
  final t = (p['tilt'] as num?) ?? 0.0;
  final ts = (p['timestamp'] as num?) ?? 0;
  // Trim trailing defaults so quick taps / mouse strokes (no real
  // pressure or timestamp) compact to just [x, y].
  if (ts == 0 && t == 0.0 && pr == 0.5) return <num>[x, y];
  if (ts == 0 && t == 0.0) return <num>[x, y, pr];
  if (ts == 0) return <num>[x, y, pr, t];
  return <num>[x, y, pr, t, ts];
}
