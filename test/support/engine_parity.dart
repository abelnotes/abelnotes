// Shared by the native fixture test (test/engine_outputs_test.dart) and the
// browser bench (test/web/abnn_wasm_bench.dart): the stroke groups both run
// and the record each makes of the router's and the OCR model's outputs.
import 'dart:typed_data';

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// The fixture file both compare against.
const engineOutputsFixture = 'test/fixtures/region_router/engine_outputs.json';

/// A group of test/fixtures/region_router/units.json.
List<StrokeData> unitStrokes(Map<String, dynamic> u) {
  final xy = (u['xy'] as List).cast<num>();
  final st = (u['starts'] as List).cast<int>();
  return [
    for (var s = 0; s < st.length; s++)
      StrokeData(points: [
        for (var i = st[s]; i < (s + 1 < st.length ? st[s + 1] : xy.length ~/ 2); i++)
          StrokePoint(x: xy[2 * i].toDouble(), y: xy[2 * i + 1].toDouble()),
      ]),
  ];
}

/// A test/fixtures/circuits file (flat x, y per stroke) as one group.
List<StrokeData> circuitStrokes(Map<String, dynamic> j) => [
      for (final s in (j['strokes'] as List))
        StrokeData(points: [
          for (var i = 0; i + 1 < (s as List).length; i += 2)
            StrokePoint(x: (s[i] as num).toDouble(), y: (s[i + 1] as num).toDouble()),
        ]),
    ];

/// Exact fingerprint of a float array (its bits), the same on the VM and in JS.
String floatsHash(Float32List v) {
  final bits = Uint32List.view(Float32List.fromList(v).buffer);
  var a = 1, b = 7;
  for (final x in bits) {
    a = (a * 31 + (x & 0xffff)) % 1000003;
    b = (b * 37 + (x >> 16)) % 1000033;
  }
  return '${v.length}:$a:$b';
}

/// Every 97th value: enough to see drift without storing whole outputs.
List<double> sample(Float32List v) => [for (var i = 0; i < v.length; i += 97) v[i]];

List<StrokeData> _moved(List<StrokeData> ss, double k, double dx, double dy) => [
      for (final s in ss)
        StrokeData(points: [for (final p in s.points) StrokePoint(x: p.x * k + dx, y: p.y * k + dy)]),
    ];

/// The groups both sides run: the router fixtures, each circuit fixture whole,
/// and the text units rescaled and joined into longer lines (more OCR cases).
List<(String, List<StrokeData>)> parityGroups(
    Map<String, dynamic> units, List<(String, Map<String, dynamic>)> circuits) {
  final us = [for (final u in units['units'] as List) u as Map<String, dynamic>];
  final out = <(String, List<StrokeData>)>[
    for (final (i, u) in us.indexed) ('unit$i-${u['label']}', unitStrokes(u)),
    for (final (name, j) in circuits) (name, circuitStrokes(j)),
  ];
  final texts = [for (final u in us) if (u['label'] == 'text') unitStrokes(u)];
  for (final k in [0.6, 1.7, 3.0]) {
    for (final (i, t) in texts.indexed) {
      out.add(('text$i-s${(k * 10).round()}', _moved(t, k, 13, -7)));
    }
  }
  // Every text unit after the previous one's right edge, on one baseline.
  final joined = <StrokeData>[];
  var right = 0.0;
  for (final t in [...texts, ...texts.reversed]) {
    var x0 = double.infinity, x1 = -double.infinity, y0 = double.infinity;
    for (final s in t) {
      for (final p in s.points) {
        x0 = p.x < x0 ? p.x : x0;
        x1 = p.x > x1 ? p.x : x1;
        y0 = p.y < y0 ? p.y : y0;
      }
    }
    joined.addAll(_moved(t, 1, right - x0 + (joined.isEmpty ? 0 : 18), -y0));
    right += x1 - x0 + (joined.isEmpty ? 0 : 18);
  }
  out.add(('text-joined', joined));
  return out;
}
