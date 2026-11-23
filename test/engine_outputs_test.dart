// The router's and the OCR model's outputs on the native engine, pinned in
// test/fixtures/region_router/engine_outputs.json so the WebAssembly build can
// be held to them in a browser (tool/web_abnn_bench.sh).
// ABELNOTES_UPDATE_FIXTURES=1 rewrites the file.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/search/ink_decode.dart';
import 'package:abelnotes/features/search/ink_recognizer.dart';
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/region_router.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/engine_parity.dart';

Future<Map<String, Object>> _record(
    String name, List<StrokeData> strokes, RegionRouter router, InkRecognizer rec) async {
  final inp = (await router.inputsAsync(strokes))!;
  final p = (await router.classifyAsync(strokes))!;
  final segments = <Map<String, Object>>[];
  for (final seg in segmentInk(strokes)) {
    final o = (await rec.debugRunAsync(seg))!;
    segments.add({
      'raster': floatsHash(await rec.rasterAsync(seg)),
      'frames': o.frames,
      'classes': o.classes,
      'sample': sample(o.probs),
      'lines': [for (final l in await rec.recognizeAsync(seg)) l.alt ? '~${l.text}' : l.text],
    });
  }
  return {
    'name': name,
    'feats': inp.feats.toList(),
    'glob': floatsHash(inp.glob),
    'local': floatsHash(inp.local),
    'probs': [p.text, p.formula, p.circuit, p.drawing],
    'segments': segments,
  };
}

void main() {
  final router = RegionRouter.open(File(regionRouterAsset).readAsBytesSync());
  final meta = InkModelMeta.fromJson(
      jsonDecode(File('assets/models/handwriting_text.json').readAsStringSync())
          as Map<String, dynamic>);
  final rec = InkRecognizer.open(File('assets/models/handwriting_text.abnn').readAsBytesSync(), meta,
      lexicon: InkLexicon.parse(File('assets/models/handwriting_lexicon.tsv').readAsStringSync()));
  final skip = router == null || rec == null
      ? 'native engine (packages/circuit_engine/src/build) missing'
      : false;

  test('native outputs match the pinned fixture', () async {
    final units = jsonDecode(File('test/fixtures/region_router/units.json').readAsStringSync())
        as Map<String, dynamic>;
    final circuits = [
      for (final f in (Directory('test/fixtures/circuits').listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path))))
        (f.uri.pathSegments.last, jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
    ];
    final groups = [
      for (final (name, strokes) in parityGroups(units, circuits))
        await _record(name, strokes, router!, rec!),
    ];
    final file = File(engineOutputsFixture);
    if (Platform.environment['ABELNOTES_UPDATE_FIXTURES'] == '1') {
      file.writeAsStringSync('${jsonEncode({'groups': groups})}\n');
    }
    final want = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['groups'] as List;
    expect(groups.length, want.length);
    // Pinned on the dev machine; another compiler (CI) rounds the last float
    // bits differently, so there only the high half of each value must match.
    final exact = Platform.environment['CI'] == null;
    final tol = exact ? 1e-6 : 1e-3;
    String hash(Object? h) {
      if (exact) return h as String;
      final p = (h as String).split(':');
      return '${p[0]}:${p[2]}';
    }
    var segs = 0, lines = 0;
    for (var g = 0; g < groups.length; g++) {
      final a = groups[g], b = want[g] as Map<String, dynamic>;
      final why = a['name'] as String;
      expect(hash(a['glob']), hash(b['glob']), reason: why);
      expect(hash(a['local']), hash(b['local']), reason: why);
      void close(List x, List y, double tol) {
        expect(x.length, y.length, reason: why);
        for (var i = 0; i < x.length; i++) {
          final u = (x[i] as num).toDouble(), v = (y[i] as num).toDouble();
          expect((u - v).abs() / math.max(1, v.abs()), lessThanOrEqualTo(tol), reason: '$why $i');
        }
      }

      close(a['feats'] as List, b['feats'] as List, tol);
      close(a['probs'] as List, b['probs'] as List, tol);
      final sa = a['segments'] as List, sb = b['segments'] as List;
      expect(sa.length, sb.length, reason: why);
      for (var s = 0; s < sa.length; s++) {
        final x = sa[s] as Map, y = sb[s] as Map;
        expect(hash(x['raster']), hash(y['raster']), reason: '$why seg $s');
        close(x['sample'] as List, y['sample'] as List, tol);
        expect(x['lines'], y['lines'], reason: '$why seg $s');
        segs++;
        lines += (x['lines'] as List).length;
      }
    }
    // ignore: avoid_print
    print('${groups.length} groups, $segs segments, $lines lines');
  }, skip: skip);

  tearDownAll(() {
    router?.dispose();
    rec?.dispose();
  });
}
