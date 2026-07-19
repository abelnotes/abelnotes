import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart'
    show decodePageData;
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Caches small PNG previews of notebook pages on disk.
///
/// Thumbnails are stored under:
///   HandWriter/thumbnails/<notebookId>.png
///
/// Rendering runs on the main isolate via [ui.PictureRecorder] — it is cheap
/// for vector content and is fire-and-forget (failures degrade to gradient
/// placeholder in the library UI).
class ThumbnailService {
  /// Physical pixel size of stored thumbnails.
  static const int thumbWidth = 360;
  static const int thumbHeight = 504; // 5:7 aspect matches A4 portrait

  late String _thumbsDir;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationDocumentsDirectory();
    _thumbsDir = p.join(appDir.path, AppConfig.appDirName, AppConfig.thumbnailsDir);
    await Directory(_thumbsDir).create(recursive: true);
    _initialized = true;
  }

  String thumbnailPath(String notebookId) =>
      p.join(_thumbsDir, '$notebookId.png');

  Future<bool> hasThumbnail(String notebookId) async {
    if (!_initialized) await init();
    return File(thumbnailPath(notebookId)).exists();
  }

  /// Returns the age of the cached thumbnail, or null if missing.
  Future<Duration?> thumbnailAge(String notebookId) async {
    if (!_initialized) await init();
    final file = File(thumbnailPath(notebookId));
    if (!await file.exists()) return null;
    final stat = await file.stat();
    return DateTime.now().difference(stat.modified);
  }

  /// Renders [page] offscreen and writes the PNG to disk.
  /// Returns the written path, or null on failure.
  ///
  /// [imageCache] and [assetBytes]: the canvas render engine looks up image
  /// elements by their `assetPath` inside `imageCache`.  If the caller's
  /// cache doesn't contain a needed image (library-screen lazy-render
  /// path, or thumbnails rendered before the canvas decoded its assets),
  /// we fall back to decoding the raw bytes from [assetBytes] on the fly.
  /// Without this fallback the PNG shows a blank rectangle where every
  /// image element would appear (the "thumbnail immagini blank" bug).
  Future<String?> renderAndCache(
    String notebookId,
    PageData page, {
    Map<String, ui.Image> imageCache = const {},
    Map<String, Uint8List> assetBytes = const {},
  }) async {
    if (!_initialized) await init();
    try {
      // ── Collect asset paths referenced by the page's image elements ──
      final neededAssets = <String>{};
      for (final el in page.layers.content) {
        el.map(
          stroke: (_) {},
          text: (_) {},
          shape: (_) {},
          math: (_) {},
          image: (img) {
            final path = img.data.assetPath;
            if (path.isNotEmpty) neededAssets.add(path);
          },
        );
      }

      // ── Decode any needed assets that aren't in the provided cache ──
      final combinedCache = Map<String, ui.Image>.from(imageCache);
      for (final ref in neededAssets) {
        if (combinedCache.containsKey(ref)) continue;
        final bytes = assetBytes[ref];
        if (bytes == null) continue;
        try {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          combinedCache[ref] = frame.image;
          codec.dispose();
        } catch (e) {
          debugPrint('[ThumbnailService] Decode failed for asset $ref: $e');
        }
      }

      final recorder = ui.PictureRecorder();
      final size = Size(thumbWidth.toDouble(), thumbHeight.toDouble());
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));

      // Clear to white — thumbnails never show app chrome behind.
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFFFFFFFF),
      );

      CanvasRenderEngine(
        pageData: page,
        imageCache: combinedCache,
      ).paint(canvas, size);

      final picture = recorder.endRecording();
      final img = await picture.toImage(thumbWidth, thumbHeight);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      img.dispose();
      // Dispose any images we decoded ourselves (not the caller's).
      for (final ref in neededAssets) {
        if (!imageCache.containsKey(ref) && combinedCache.containsKey(ref)) {
          combinedCache[ref]!.dispose();
        }
      }
      if (data == null) return null;

      final file = File(thumbnailPath(notebookId));
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[ThumbnailService] Render failed for $notebookId: $e');
      return null;
    }
  }

  /// Lazy thumbnail generation from the local .ncnote bytes.
  /// Used when the library screen shows a notebook that never had a
  /// thumbnail cached (downloaded from the server, imported, or created
  /// before thumbnails existed).
  /// No-op if a thumbnail already exists.
  Future<String?> ensureFromNcnoteBytes(
    String notebookId,
    Uint8List ncnoteBytes,
  ) async {
    if (!_initialized) await init();
    final file = File(thumbnailPath(notebookId));
    if (await file.exists()) return file.path;
    try {
      // Minimal parse: find the first page JSON under pages/ and decode it.
      final archive = ZipDecoder().decodeBytes(ncnoteBytes);
      ArchiveFile? firstPageFile;
      const pagesPrefix = '${AppConfig.pagesDir}/';
      for (final f in archive.files) {
        if (f.name.startsWith(pagesPrefix) && f.name.endsWith('.json')) {
          if (firstPageFile == null || f.name.compareTo(firstPageFile.name) < 0) {
            firstPageFile = f;
          }
        }
      }
      if (firstPageFile == null) return null;
      final json = jsonDecode(utf8.decode(firstPageFile.content as List<int>));
      final page = decodePageData(json as Map<String, dynamic>);

      // Collect only the asset bytes referenced by this first page so the
      // thumbnail renders image elements instead of blank rectangles.
      final neededRefs = <String>{};
      for (final el in page.layers.content) {
        el.map(
          stroke: (_) {},
          text: (_) {},
          shape: (_) {},
          math: (_) {},
          image: (img) {
            final path = img.data.assetPath;
            if (path.isNotEmpty) neededRefs.add(path);
          },
        );
      }
      final assetBytes = <String, Uint8List>{};
      if (neededRefs.isNotEmpty) {
        const assetsPrefix = '${AppConfig.assetsDir}/';
        for (final f in archive.files) {
          if (!f.isFile) continue;
          if (!f.name.startsWith(assetsPrefix)) continue;
          final ref = f.name.substring(assetsPrefix.length);
          if (ref.isEmpty) continue;
          if (!neededRefs.contains(ref)) continue;
          assetBytes[ref] =
              Uint8List.fromList(f.content as List<int>);
        }
      }

      return renderAndCache(notebookId, page, assetBytes: assetBytes);
    } catch (e) {
      debugPrint('[ThumbnailService] Lazy render failed for $notebookId: $e');
      return null;
    }
  }

  Future<void> deleteThumbnail(String notebookId) async {
    if (!_initialized) await init();
    final file = File(thumbnailPath(notebookId));
    if (await file.exists()) {
      try { await file.delete(); } catch (_) {}
    }
  }

  Future<void> clearAll() async {
    if (!_initialized) await init();
    final dir = Directory(_thumbsDir);
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      try { await entry.delete(recursive: true); } catch (_) {}
    }
  }
}
