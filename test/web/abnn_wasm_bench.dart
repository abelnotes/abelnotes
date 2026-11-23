// The region router and handwriting OCR as WebAssembly (engine worker) against
// the native engine's pinned outputs (test/engine_outputs_test.dart), in a
// browser. Built and run by tool/web_abnn_bench.sh; prints one JSON line
// "ABNN_BENCH {...}" to the console.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:abelnotes/features/search/ink_decode.dart';
import 'package:abelnotes/features/search/ink_recognizer.dart';
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/region_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../support/engine_parity.dart';

Future<String> _get(String url) async => (await (await web.window.fetch(url.toJS).toDart).text().toDart).toDart;

Future<Uint8List> _asset(String key) async {
  final d = await rootBundle.load(key);
  return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{};
  try {
    final watch = Stopwatch()..start();
    final router = await RegionRouter.load(await _asset(regionRouterAsset));
    report['routerLoadMs'] = watch.elapsedMilliseconds;
    final meta = InkModelMeta.fromJson(
        jsonDecode(await rootBundle.loadString('assets/models/handwriting_text.json')) as Map<String, dynamic>);
    watch.reset();
    final lexicon = await InkLexicon.parseAsync(
        await rootBundle.loadString('assets/models/handwriting_lexicon.tsv'), () => Future<void>.delayed(Duration.zero));
    report['lexiconMs'] = watch.elapsedMilliseconds;
    watch.reset();
    final rec = await InkRecognizer.load(await _asset('assets/models/handwriting_text.abnn'), meta, lexicon: lexicon);
    report['ocrLoadMs'] = watch.elapsedMilliseconds;
    if (router == null || rec == null) throw StateError('engine did not load (router $router, ocr $rec)');

    final index = jsonDecode(await _get('bench/index.json')) as Map<String, dynamic>;
    final units = jsonDecode(await _get('bench/units.json')) as Map<String, dynamic>;
    final want = (jsonDecode(await _get('bench/engine_outputs.json')) as Map<String, dynamic>)['groups'] as List;
    final circuits = [
      for (final n in (index['circuits'] as List).cast<String>())
        (n, jsonDecode(await _get('bench/$n')) as Map<String, dynamic>),
    ];
    final groups = parityGroups(units, circuits);

    var featWorst = 0.0, probWorst = 0.0, onnxWorst = 0.0, sampleWorst = 0.0;
    var viewsSame = 0, rasterSame = 0, linesSame = 0, segs = 0, lines = 0;
    final mismatches = <String>[];
    var routeMs = 0, ocrMs = 0, gap = 0;
    // The UI thread's longest stall while the worker runs.
    var last = 0;
    final clock = Stopwatch()..start();
    final tick = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = clock.elapsedMilliseconds;
      gap = math.max(gap, now - last);
      last = now;
    });
    if (groups.length != want.length) mismatches.add('group count ${groups.length} vs ${want.length}');
    for (var g = 0; g < math.min(groups.length, want.length); g++) {
      final (name, strokes) = groups[g];
      final w = want[g] as Map<String, dynamic>;
      final inp = (await router.inputsAsync(strokes))!;
      for (var i = 0; i < 24; i++) {
        final v = ((w['feats'] as List)[i] as num).toDouble();
        featWorst = math.max(featWorst, (inp.feats[i] - v).abs() / math.max(1, v.abs()));
      }
      if (floatsHash(inp.glob) == w['glob'] && floatsHash(inp.local) == w['local']) {
        viewsSame++;
      } else {
        mismatches.add('$name views');
      }
      watch.reset();
      final p = (await router.classifyAsync(strokes))!;
      routeMs += watch.elapsedMilliseconds;
      final got = [p.text, p.formula, p.circuit, p.drawing];
      for (var i = 0; i < 4; i++) {
        probWorst = math.max(probWorst, (got[i] - ((w['probs'] as List)[i] as num).toDouble()).abs());
      }
      if (g < (units['units'] as List).length) {
        final onnx = RegionProbs.fromLogits(
            [for (final v in ((units['units'] as List)[g] as Map)['logits'] as List) (v as num).toDouble()]);
        for (var i = 0; i < 4; i++) {
          onnxWorst = math.max(onnxWorst, (got[i] - [onnx.text, onnx.formula, onnx.circuit, onnx.drawing][i]).abs());
        }
      }
      final ws = w['segments'] as List, ss = segmentInk(strokes);
      if (ss.length != ws.length) mismatches.add('$name segments ${ss.length} vs ${ws.length}');
      for (var s = 0; s < math.min(ss.length, ws.length); s++) {
        final ref = ws[s] as Map<String, dynamic>;
        segs++;
        if (floatsHash(await rec.rasterAsync(ss[s])) == ref['raster']) {
          rasterSame++;
        } else {
          mismatches.add('$name seg $s raster');
        }
        final o = (await rec.debugRunAsync(ss[s]))!;
        final smp = sample(o.probs), rs = (ref['sample'] as List);
        if (smp.length != rs.length || o.frames != ref['frames'] || o.classes != ref['classes']) {
          mismatches.add('$name seg $s output shape');
        } else {
          for (var i = 0; i < smp.length; i++) {
            sampleWorst = math.max(sampleWorst, (smp[i] - (rs[i] as num).toDouble()).abs());
          }
        }
        watch.reset();
        final ls = await rec.recognizeAsync(ss[s]);
        ocrMs += watch.elapsedMilliseconds;
        final texts = [for (final l in ls) l.alt ? '~${l.text}' : l.text];
        lines += texts.length;
        if (jsonEncode(texts) == jsonEncode(ref['lines'])) {
          linesSame++;
        } else {
          mismatches.add('$name seg $s lines $texts vs ${ref['lines']}');
        }
      }
    }
    tick.cancel();
    report.addAll({
      'groups': groups.length,
      'segments': segs,
      'lines': lines,
      'viewsSame': viewsSame,
      'rasterSame': rasterSame,
      'linesSame': linesSame,
      'featWorstRel': featWorst,
      'probWorstVsNative': probWorst,
      'probWorstVsOnnx': onnxWorst,
      'ocrProbWorst': sampleWorst,
      'routeMsPerGroup': routeMs / groups.length,
      'ocrMsPerSegment': segs == 0 ? 0 : ocrMs / segs,
      'uiGapMs': gap,
      'mismatches': mismatches,
    });
  } catch (e, st) {
    report['error'] = '$e\n$st';
  }
  web.console.log('ABNN_BENCH ${jsonEncode(report)}'.toJS);
}
