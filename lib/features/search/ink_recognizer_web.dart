import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/engine_worker_web.dart';
import 'package:abelnotes/features/search/ink_decode.dart';
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Handwriting lines on the web: raster and model (abnn) as WebAssembly in the
/// engine's worker, decoding here; only the async forms answer.
class InkRecognizer {
  InkRecognizer._(this._w, this._m, this._meta, this._lexicon);

  final EngineWorker _w;
  final int _m;
  final InkModelMeta _meta;
  final InkLexicon? _lexicon;
  bool _disposed = false;

  /// Native only: on the web use [load].
  static InkRecognizer? open(Uint8List model, InkModelMeta meta, {InkLexicon? lexicon}) =>
      null;

  static Future<InkRecognizer?> load(Uint8List model, InkModelMeta meta,
      {InkLexicon? lexicon}) async {
    final w = await EngineWorker.shared();
    if (w == null) return null;
    try {
      final m = ((await w.ask('abnnLoad', {'bytes': model.toJS})) as JSNumber).toDartInt;
      return m == 0 ? null : InkRecognizer._(w, m, meta, lexicon);
    } catch (_) {
      return null;
    }
  }

  /// Native only: on the web use [recognizeAsync].
  List<InkLine> recognizePage(PageData page, {bool Function(InkSegment seg)? keep}) =>
      const [];

  List<InkLine> recognize(InkSegment seg) => const [];

  /// The segment's line (lexicon reading first, then the plain one if it differs).
  Future<List<InkLine>> recognizeAsync(InkSegment seg) async {
    final o = await debugRunAsync(seg);
    if (o == null || _disposed) return const [];
    return decodeLines(o.probs, o.frames, o.classes, seg, o.geometry, _meta, _lexicon);
  }

  /// The model's output for [seg], for parity tests.
  Future<({Float32List probs, int frames, int classes, InkRaster geometry})?> debugRunAsync(
      InkSegment seg) async {
    if (_disposed) return null;
    final r = rasterGeometry(seg, _meta);
    final lw = math.max(1.0, (_meta.lineWidth * r.scale / 2).roundToDouble());
    final o = await _w.ask('ocr', {
      'm': _m.toJS,
      'xy': r.xy.toJS,
      'starts': r.starts.toJS,
      'lw': lw.toJS,
      'w': r.width.toJS,
      'h': _meta.height.toJS,
    });
    if (o == null) return null;
    final d = o as JSObject;
    return (
      probs: (d['probs'] as JSFloat32Array).toDart,
      frames: (d['frames'] as JSNumber).toDartInt,
      classes: (d['classes'] as JSNumber).toDartInt,
      geometry: r,
    );
  }

  /// The model's input for [seg] (3 x height x width), for tests.
  Future<Float32List> rasterAsync(InkSegment seg) async {
    final r = rasterGeometry(seg, _meta);
    final lw = math.max(1.0, (_meta.lineWidth * r.scale / 2).roundToDouble());
    final o = await _w.ask('raster', {
      'xy': r.xy.toJS,
      'starts': r.starts.toJS,
      'lw': lw.toJS,
      'w': r.width.toJS,
      'h': _meta.height.toJS,
    });
    return (o as JSFloat32Array).toDart;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _w.ask('abnnFree', {'m': _m.toJS}).ignore();
  }
}
