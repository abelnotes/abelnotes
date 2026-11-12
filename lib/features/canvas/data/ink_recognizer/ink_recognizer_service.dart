// Runs ink-to-LaTeX recognition off the UI thread, on a long-lived isolate.
//
// The weights ship as an asset and are copied to disk once, because the
// isolate loads by path: one parse per session instead of one per request,
// so a request carries only the extracted features (a couple of kilobytes).
// Feature extraction stays on the calling isolate: microseconds of work.
// The web has no isolates or files, so there the model runs inline.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:abelnotes/core/platform/io.dart';
import 'package:abelnotes/features/modules/bundled_model.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'ink_features.dart';
import 'ink_to_latex.dart';
import 'latex_delimiters.dart';
import 'model_file.dart';

const String kInkModelFileName = 'math_ink.ablm';

const String kBundledInkModelAsset = 'assets/models/$kInkModelFileName';

/// sha256 of the bundled model; test/ink_model_asset_test.dart pins it.
const String kBundledInkModelSha256 =
    '4e247ea7fa410fdccbfa349df53de5895c94da2b65ae6268c699871bee8b24b3';

/// The recognizer, or null when this build carries no model. Auto-disposed:
/// a module switched off in Settings frees its isolate.
final inkRecognizerProvider = FutureProvider.autoDispose<InkRecognizer?>((ref) async {
  if (kIsWeb) return InkRecognizer.loadInline();
  final dir = await getApplicationSupportDirectory();
  final path = InkRecognizer.pathIn(dir.path);
  await installBundledModel(path, kBundledInkModelSha256, () => rootBundle.load(kBundledInkModelAsset));
  final recognizer = await InkRecognizer.load(path);
  ref.onDispose(() => recognizer?.dispose());
  return recognizer;
});

/// Recognition result, or the reason there isn't one.
class RecognitionResult {
  const RecognitionResult.success(this.latex, this.milliseconds, [this.confidence = 1])
      : error = null;
  const RecognitionResult.failure(this.error)
      : latex = null,
        milliseconds = 0,
        confidence = 0;

  final String? latex;
  final String? error;
  final int milliseconds;

  /// Lowest probability of any decoded token: low means some symbol was a guess.
  final double confidence;

  bool get ok => latex != null && latex!.isNotEmpty;
}

/// Owns the recognition isolate. Create with [load]; call [dispose] when done.
class InkRecognizer {
  InkRecognizer._(Isolate this._isolate, SendPort this._toIsolate, Stream<dynamic> this._responses, this.maxTargetLen)
      : _inline = null;
  InkRecognizer._inline(InkToLatexModel this._inline)
      : _isolate = null,
        _toIsolate = null,
        _responses = null,
        maxTargetLen = _inline.config.maxTargetLen;

  final Isolate? _isolate;
  final SendPort? _toIsolate;
  final Stream<dynamic>? _responses;

  /// Web has no isolates or files: the bundled model runs on the UI thread.
  final InkToLatexModel? _inline;

  /// Longest token sequence the loaded decoder can emit.
  final int maxTargetLen;

  var _nextId = 0;
  var _disposed = false;

  /// Spawns the isolate and waits for it to parse [path]; null if the file
  /// is absent or unreadable.
  static Future<InkRecognizer?> load(String path) async {
    if (!File(path).existsSync()) return null;

    final ready = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(_isolateMain, [ready.sendPort, path],
          debugName: 'ink-recognizer');
    } catch (e) {
      ready.close();
      debugPrint('[ink] isolate spawn failed: $e');
      return null;
    }

    final responses = ready.asBroadcastStream();
    final handshake = await responses.first;
    if (handshake is! _Ready) {
      isolate.kill(priority: Isolate.immediate);
      ready.close();
      debugPrint('[ink] model load failed: '
          '${handshake is _Failed ? handshake.message : handshake}');
      return null;
    }
    return InkRecognizer._(isolate, handshake.port, responses, handshake.maxTargetLen);
  }

  /// Null when this build carries no model.
  static Future<InkRecognizer?> loadInline() async {
    try {
      final data = await rootBundle.load(kBundledInkModelAsset);
      return InkRecognizer._inline(InkToLatexModel.fromFile(
          await ModelFile.parseAsync(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))));
    } catch (e) {
      debugPrint('[ink] model load failed: $e');
      return null;
    }
  }

  /// Where the bundled model is installed.
  static String pathIn(String supportDirectory) =>
      '$supportDirectory${Platform.pathSeparator}models'
      '${Platform.pathSeparator}$kInkModelFileName';

  /// Recognizes [strokes] as a single expression.
  ///
  /// Strokes should be the user's selection in page coordinates; scale and
  /// position are normalized away by [extractFeatures], so no pre-processing is
  /// needed at the call site.
  Future<RecognitionResult> recognize(List<StrokeData> strokes) async {
    if (_disposed) return const RecognitionResult.failure('recognizer disposed');
    if (strokes.isEmpty) return const RecognitionResult.failure('nothing selected');

    final features = extractFeatures(strokes);
    if (features.isEmpty) {
      return const RecognitionResult.failure('selection has no ink');
    }

    final inline = _inline;
    if (inline != null) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final watch = Stopwatch()..start();
      try {
        final (latex, confidence) = _decode(inline, features.values, features.pointCount);
        return RecognitionResult.success(latex, watch.elapsedMilliseconds, confidence);
      } catch (e) {
        return RecognitionResult.failure('$e');
      }
    }
    final id = _nextId++;
    _toIsolate!.send(_Request(id, features.values, features.pointCount));
    final reply = await _responses!.firstWhere(
      (m) => m is _Response && m.id == id,
      orElse: () => _Response(id, null, 0, 'isolate closed', 0),
    ) as _Response;

    if (reply.error != null) return RecognitionResult.failure(reply.error);
    return RecognitionResult.success(reply.latex ?? '', reply.milliseconds, reply.confidence);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
  }

  static (String, double) _decode(InkToLatexModel model, Float32List features, int pointCount) {
    final encoded = model.encode(InkFeatures(features, pointCount));
    final probs = <double>[];
    final tokens = model.decode(encoded, probs: probs);
    return (stretchDelimiters(balanceBraces(model.detokenize(tokens))), probs.fold(1.0, math.min));
  }

  // ── isolate side ──

  static void _isolateMain(List<dynamic> args) {
    final ready = args[0] as SendPort;
    final path = args[1] as String;

    final InkToLatexModel model;
    try {
      final bytes = File(path).readAsBytesSync();
      model = InkToLatexModel.fromFile(ModelFile.parse(bytes));
    } catch (e) {
      ready.send(_Failed('$e'));
      return;
    }

    final inbox = ReceivePort();
    ready.send(_Ready(inbox.sendPort, model.config.maxTargetLen));

    inbox.listen((message) {
      if (message is! _Request) return;
      final watch = Stopwatch()..start();
      try {
        final (latex, confidence) = _decode(model, message.features, message.pointCount);
        ready.send(_Response(message.id, latex, watch.elapsedMilliseconds, null, confidence));
      } catch (e) {
        ready.send(_Response(message.id, null, watch.elapsedMilliseconds, '$e', 0));
      }
    });
  }
}

class _Ready {
  _Ready(this.port, this.maxTargetLen);
  final SendPort port;
  final int maxTargetLen;
}

class _Failed {
  _Failed(this.message);
  final String message;
}

class _Request {
  _Request(this.id, this.features, this.pointCount);
  final int id;
  final Float32List features;
  final int pointCount;
}

class _Response {
  _Response(this.id, this.latex, this.milliseconds, this.error, this.confidence);
  final int id;
  final String? latex;
  final int milliseconds;
  final String? error;
  final double confidence;
}
