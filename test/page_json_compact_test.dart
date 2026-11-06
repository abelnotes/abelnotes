import 'dart:convert';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter_test/flutter_test.dart';

// The page encoder splices cached per-element JSON; it must stay byte-identical
// to rounding + compacting the whole toJson() tree, which these helpers redo.
Object? _round(Object? v) {
  if (v is double) return v.isFinite ? (v * 1000).round() / 1000 : v;
  if (v is Map) return {for (final e in v.entries) e.key as String: _round(e.value)};
  if (v is List) return v.map(_round).toList();
  return v;
}

void _compact(Object? v) {
  if (v is Map) {
    if (v['type'] == 'stroke' && v['data'] is Map && (v['data'] as Map)['points'] is List) {
      final pts = (v['data'] as Map)['points'] as List;
      for (var i = 0; i < pts.length; i++) {
        final p = pts[i];
        if (p is Map) {
          final x = p['x'] as num, y = p['y'] as num;
          final pr = (p['pressure'] as num?) ?? 0.5, t = (p['tilt'] as num?) ?? 0.0, ts = (p['timestamp'] as num?) ?? 0;
          pts[i] = ts == 0 && t == 0.0 && pr == 0.5 ? [x, y] : ts == 0 && t == 0.0 ? [x, y, pr] : ts == 0 ? [x, y, pr, t] : [x, y, pr, t, ts];
        }
      }
    }
    v.forEach((_, val) => _compact(val));
  } else if (v is List) {
    v.forEach(_compact);
  }
}

String _treeEncoded(PageData page) {
  final r = _round(page.toJson());
  _compact(r);
  return jsonEncode(r);
}

ContentElement _stroke(String id, List<StrokePoint> points) =>
    ContentElement.stroke(id: id, zIndex: 0, data: StrokeData(points: points));

PageData _page(List<ContentElement> content) => PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 595.123456,
      height: 842,
      layers: RenderingLayers(content: content),
    );

void main() {
  test('every point form matches the tree encoder', () {
    final page = _page([
      _stroke('plain', const [StrokePoint(x: 1.23456, y: -2.0004), StrokePoint(x: 0, y: 1e-4)]),
      _stroke('pressure', const [StrokePoint(x: 1, y: 2, pressure: 0.70049)]),
      _stroke('tilt', const [StrokePoint(x: 1, y: 2, tilt: 0.3)]),
      _stroke('time', const [StrokePoint(x: 1, y: 2, timestamp: 17)]),
      _stroke('rounds to default', const [StrokePoint(x: 1, y: 2, pressure: 0.50004, tilt: 0.0001)]),
      _stroke('empty', const []),
      const ContentElement.text(
          id: 't', zIndex: 2, data: TextData(x: 1, y: 2, width: 3, height: 4, content: '"content":[] "points":[]')),
      const ContentElement.unknown(id: 'u', zIndex: 3, raw: {'type': 'future', 'id': 'u', 'v': 1.23456}),
    ]);
    expect(compactPageJson(page), _treeEncoded(page));
    expect(compactPageJson(page), _treeEncoded(page), reason: 'cached second pass');
  });

  test('an empty page and a non-finite point match the tree encoder', () {
    expect(compactPageJson(_page(const [])), _treeEncoded(_page(const [])));
    final odd = _page([_stroke('inf', const [StrokePoint(x: double.infinity, y: 2)])]);
    expect(() => compactPageJson(odd), throwsA(isA<JsonUnsupportedObjectError>()));
    expect(() => _treeEncoded(odd), throwsA(isA<JsonUnsupportedObjectError>()));
  });

  test('a changed stroke is re-encoded, not served from the cache', () {
    final a = _stroke('s', const [StrokePoint(x: 1, y: 2)]);
    final before = compactPageJson(_page([a]));
    final moved = (a as StrokeElement).copyWith.data(points: const [StrokePoint(x: 5, y: 6)]);
    expect(compactPageJson(_page([moved])), isNot(before));
    expect(compactPageJson(_page([moved])), _treeEncoded(_page([moved])));
  });

  test('decoding reads compact and map points alike, other elements untouched', () {
    final page = _page([
      _stroke('a', const [
        StrokePoint(x: 1.5, y: 2),
        StrokePoint(x: 3, y: 4, pressure: 0.25),
        StrokePoint(x: 5, y: 6, pressure: 0.5, tilt: 0.3),
        StrokePoint(x: 7, y: 8, pressure: 0.9, tilt: 0.1, timestamp: 42),
      ]),
      const ContentElement.text(
          id: 't', zIndex: 1, data: TextData(x: 1, y: 2, width: 10, height: 10, content: 'hi')),
      _stroke('b', const [StrokePoint(x: 9, y: 9)]),
    ]).copyWith(width: 595);
    final compact = jsonDecode(compactPageJson(page)) as Map<String, dynamic>;
    final maps = jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>;
    expect(decodePageData(compact), page);
    expect(decodePageData(maps), page);
  });

  test('a malformed point still fails the page, as before', () {
    final json = jsonDecode(compactPageJson(_page([
      _stroke('a', const [StrokePoint(x: 1, y: 2)]),
    ]))) as Map<String, dynamic>;
    ((json['layers']['content'] as List).first['data']['points'] as List)[0] = 'x';
    expect(() => decodePageData(json), throwsA(isA<TypeError>()));
  });
}
