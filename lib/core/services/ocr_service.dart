import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// On-device handwriting recognition (HTR).
///
/// Design goal: add HTR **without bloating the binary**. No ML model is
/// bundled or linked into the base app — recognition is delegated to the
/// OS's own on-device recognizer where one exists:
///   - iOS / macOS → Apple Vision (`VNRecognizeTextRequest`), free,
///     on-device, no model shipped by us. See the native handlers in
///     ios/Runner/AppDelegate.swift and macos/Runner/MainFlutterWindow.swift.
///   - everything else (Linux, Windows, Android for now) → unsupported;
///     [isSupported] is false and [recognizePage] returns null. Wire a
///     platform-native recognizer (ML Kit Digital Ink on Android, Windows
///     Ink Analysis) or an optional downloaded model later, still without
///     touching the base binary.
///
/// Recognition is lazy — invoked only when the user asks ("Recognize
/// handwriting") or when building a search index — never per stroke, so the
/// idle CPU/RAM cost is zero.
abstract class OcrService {
  /// True if this platform can recognize handwriting right now.
  bool get isSupported;

  /// Rasterizes [page]'s ink and runs on-device HTR, returning a text layer
  /// in **page-logical points** (reuses [PdfTextLayer], so search and the
  /// text-selection overlay work unchanged), or null if unsupported or
  /// nothing was recognized.
  Future<PdfTextLayer?> recognizePage(PageData page);
}

/// Picks the platform implementation, or a no-op elsewhere.
OcrService createOcrService() {
  if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
    return _AppleVisionOcrService();
  }
  return const _UnsupportedOcrService();
}

class _UnsupportedOcrService implements OcrService {
  const _UnsupportedOcrService();
  @override
  bool get isSupported => false;
  @override
  Future<PdfTextLayer?> recognizePage(PageData page) async => null;
}

class _AppleVisionOcrService implements OcrService {
  static const MethodChannel _channel = MethodChannel('handwriter/ocr');

  /// Target longest raster side handed to Vision. Big enough that small
  /// handwriting stays legible, capped so a huge page doesn't blow memory.
  static const double _targetMaxSide = 2048;

  @override
  bool get isSupported => true;

  @override
  Future<PdfTextLayer?> recognizePage(PageData page) async {
    if (page.width <= 0 || page.height <= 0) return null;
    final pngBytes = await _rasterize(page);
    if (pngBytes == null) return null;

    // Native returns a list of {text, confidence, x, y, w, h} where the box
    // is TOP-LEFT-origin normalized (0..1) — the Y-flip from Vision's
    // bottom-left origin is done natively, next to Vision, so the mapping
    // here is a plain multiply into page-logical points.
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeMethod<List<Object?>>('recognize', {
        'png': pngBytes,
      });
    } on PlatformException catch (e) {
      debugPrint('[OCR] native recognize failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null; // runner without the native handler
    }
    if (raw == null || raw.isEmpty) return null;

    final runs = <PdfTextRun>[];
    double confidenceSum = 0;
    int confidenceCount = 0;
    for (final item in raw) {
      final m = (item as Map?)?.cast<Object?, Object?>();
      if (m == null) continue;
      final text = (m['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      final nx = (m['x'] as num?)?.toDouble() ?? 0;
      final ny = (m['y'] as num?)?.toDouble() ?? 0;
      final nw = (m['w'] as num?)?.toDouble() ?? 0;
      final nh = (m['h'] as num?)?.toDouble() ?? 0;
      runs.add(PdfTextRun(
        text: text,
        x: nx * page.width,
        y: ny * page.height,
        width: nw * page.width,
        height: nh * page.height,
      ));
      final c = (m['confidence'] as num?)?.toDouble();
      if (c != null) {
        confidenceSum += c;
        confidenceCount++;
      }
    }
    if (runs.isEmpty) return null;

    return PdfTextLayer(
      sourceAssetPath: '', // recognized from ink, not a PDF raster
      source: 'ocr',
      confidence: confidenceCount > 0 ? confidenceSum / confidenceCount : null,
      runs: runs,
    );
  }

  /// Renders the page's ink to a white-background PNG whose pixel dimensions
  /// are exactly proportional to the page's logical size. That keeps the
  /// render engine's aspect-fit letterbox offsets at zero, so Vision's
  /// normalized boxes map straight back to page-logical points with no
  /// centering correction.
  Future<Uint8List?> _rasterize(PageData page) async {
    try {
      final maxSide =
          page.width >= page.height ? page.width : page.height;
      final scale = (_targetMaxSide / maxSide).clamp(1.0, 4.0);
      final pxW = (page.width * scale).round();
      final pxH = (page.height * scale).round();
      if (pxW <= 0 || pxH <= 0) return null;

      final recorder = ui.PictureRecorder();
      final size = ui.Size(pxW.toDouble(), pxH.toDouble());
      final canvas =
          ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size.width, size.height),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      // Empty image cache on purpose: HTR only cares about ink strokes, and
      // rendering on clean white is what Vision handles best. Embedded PDF
      // page text already has its own layer and isn't re-recognized here.
      CanvasRenderEngine(pageData: page).paint(canvas, size);

      final picture = recorder.endRecording();
      final img = await picture.toImage(pxW, pxH);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      img.dispose();
      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[OCR] rasterize failed: $e');
      return null;
    }
  }
}
