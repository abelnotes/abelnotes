// Region router: C inputs and logits against the Python reference (fixtures:
// synthetic strokes, expected features, view sums and onnxruntime logits), and
// the search gate in the indexer's extraction.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/search/ink_recognizer.dart';
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/region_router.dart';
import 'package:abelnotes/features/search/search_indexer.dart' show ocrGate;
import 'package:abelnotes/shared/models/ncnote_format.dart';

List<StrokeData> _strokes(Map<String, dynamic> u) {
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

void main() {
  final model = File(regionRouterAsset);
  final router = model.existsSync() ? RegionRouter.open(model.readAsBytesSync()) : null;
  final skip = router == null ? 'native engine (packages/circuit_engine/src/build) missing' : false;
  final fx = jsonDecode(File('test/fixtures/region_router/units.json').readAsStringSync())
      as Map<String, dynamic>;
  final units = (fx['units'] as List).cast<Map<String, dynamic>>();
  tearDownAll(() => router?.dispose());

  test('softmax and ranking', () {
    final p = RegionProbs.fromLogits([0, 2, 1, -1]);
    expect(p.text + p.formula + p.circuit + p.drawing, closeTo(1, 1e-9));
    expect(p.top, RegionKind.formula);
    expect(p.ranked, [RegionKind.formula, RegionKind.circuit, RegionKind.text, RegionKind.drawing]);
  });

  test('fixtures cover every class', () {
    expect({for (final u in units) u['label']}, {'text', 'formula', 'circuit', 'drawing'});
  });

  test('C features and views match the Python reference', () {
    for (final u in units) {
      final r = router!.inputs(_strokes(u))!;
      final want = (u['feats'] as List).cast<num>();
      for (var i = 0; i < 24; i++) {
        final w = want[i].toDouble();
        expect((r.feats[i] - w).abs() / math.max(1, w.abs()), lessThan(1e-5),
            reason: 'feature $i');
      }
      double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);
      expect(sum(r.glob), closeTo((u['glob_sum'] as num).toDouble(), 1e-2));
      expect(sum(r.local), closeTo((u['local_sum'] as num).toDouble(), 1e-2));
    }
  }, skip: skip);

  test('C logits match onnxruntime', () {
    for (final u in units) {
      final p = router!.classify(_strokes(u))!;
      final want = RegionProbs.fromLogits(
          [for (final v in (u['logits'] as List).cast<num>()) v.toDouble()]);
      for (final k in RegionKind.values) {
        expect(p.of(k), closeTo(want.of(k), 1e-4), reason: '${u['label']} $k');
      }
      expect(p.top, want.top);
    }
  }, skip: skip);

  test('empty groups are not classified', () {
    expect(router!.classify(const []), isNull);
    expect(router.classify([const StrokeData(points: [])]), isNull);
  }, skip: skip);

  test('a single point still classifies', () {
    final p = router!.classify([
      const StrokeData(points: [StrokePoint(x: 5, y: 5)])
    ]);
    expect(p, isNotNull);
  }, skip: skip);

  test('search gate: formula lines never reach OCR, text lines do', () {
    final text = _strokes(units[0]), formula = _strokes(units[2]);
    expect(router!.classify(text)!.text, greaterThanOrEqualTo(ocrTextThreshold));
    expect(router.classify(formula)!.text, lessThan(ocrTextThreshold));
    // Both lines on one page, far apart; count what the gate lets through.
    List<StrokeData> moved(List<StrokeData> ss, double dy) => [
          for (final s in ss)
            StrokeData(points: [for (final q in s.points) StrokePoint(x: q.x, y: q.y + dy)])
        ];
    final page = PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 2000,
      height: 4000,
      layers: RenderingLayers(content: [
        for (final (i, s) in [...moved(text, 0), ...moved(formula, 2000)].indexed)
          StrokeElement(id: 's$i', zIndex: i, data: s),
      ]),
    );
    final segs = segmentInk(inkStrokes(page));
    final gate = ocrGate(router);
    final kept = segs.where(gate).toList();
    final hasText = segs.any((s) => s.y1 < 1500), hasFormula = segs.any((s) => s.y0 > 1500);
    expect(hasText && hasFormula, isTrue, reason: 'both lines segment');
    expect(kept.any((s) => s.y1 < 1500), isTrue);
    expect(kept.any((s) => s.y0 > 1500), isFalse);
    // The recognizer honours the gate.
    final meta = File('assets/models/handwriting_text.json');
    final rec = InkRecognizer.open(File('assets/models/handwriting_text.abnn').readAsBytesSync(),
        InkModelMeta.fromJson(jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>));
    if (rec != null) {
      expect(rec.recognizePage(page, keep: (_) => false), isEmpty);
      final lines = rec.recognizePage(page, keep: gate);
      expect(lines.every((l) => l.y0 < 1500), isTrue);
      rec.dispose();
    }
  }, skip: skip);
}
