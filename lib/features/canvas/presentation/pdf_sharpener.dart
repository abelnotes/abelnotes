import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:abelnotes/features/canvas/data/pdf_source_renderer.dart';
import 'package:abelnotes/features/canvas/data/pdf_sources.dart';
import 'package:abelnotes/features/canvas/data/pdf_tiles.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Sharp zoom of imported PDF pages for one open notebook: knows which image
/// assets have a source PDF and keeps the visible tiles rendered.
class PdfSharpener {
  final String notebookId;
  final PdfSourceStore store;
  late final PdfSourceRenderer _renderer = PdfSourceRenderer(store);
  late final PdfTileScheduler _scheduler;

  PdfSharpener(this.notebookId, String storeDir, {required int cacheBytes})
      : store = PdfSourceStore(storeDir) {
    _scheduler = PdfTileScheduler(
      cache: PdfTileCache(maxBytes: cacheBytes),
      render: _renderer.render,
    );
  }

  /// Bumped when tiles land or the painted level changes.
  ValueListenable<int> get version => _scheduler.version;

  bool get hasSources => _renderer.links.isNotEmpty;

  /// Re-reads `sources/` (after an import or a sync brought new files).
  Future<void> reload() async {
    _renderer.links = pdfSourceLinks(await store.loadIndexes());
  }

  List<PdfTile> tilesFor(String assetPath) => _scheduler.tilesFor(assetPath);

  /// Asks for the tiles [page] needs on screen. [visiblePage] is the part of
  /// the page on screen in page points, [screenDensity] device pixels per
  /// page point.
  void showViewport({
    required PageData page,
    required ui.Rect visiblePage,
    required double screenDensity,
    required Map<String, ui.Image> decoded,
  }) {
    if (!hasSources) return;
    final requests = <PdfTileRequest>[];
    for (final el in page.layers.content) {
      if (el is! ImageElement) continue;
      final d = el.data;
      // Rotated images would need a rotated visible rect; they keep the PNG.
      if (d.rotation != 0 || !_renderer.covers(d.assetPath)) continue;
      final png = decoded[d.assetPath];
      if (png == null || d.width <= 0 || d.height <= 0) continue;
      final box = ui.Rect.fromLTWH(d.x, d.y, d.width, d.height);
      final visible = visiblePage.intersect(box);
      if (visible.isEmpty) continue;
      requests.add(PdfTileRequest(
        assetPath: d.assetPath,
        grid: PdfTileGrid(
          widthPt: d.width,
          heightPt: d.height,
          baseDensity: png.width / d.width,
        ),
        visiblePt: d.flipHorizontal
            ? ui.Rect.fromLTRB(box.right - visible.right, visible.top - box.top,
                box.right - visible.left, visible.bottom - box.top)
            : visible.shift(-box.topLeft),
        screenDensity: screenDensity,
      ));
    }
    _scheduler.update(requests);
  }

  void dispose() {
    _scheduler.dispose();
    _renderer.dispose();
  }
}

/// Decoded-tile budget: phones and tablets get less.
int pdfTileCacheBytes(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS
        ? 48 << 20
        : 128 << 20;

/// Waits for the viewport to settle before asking for tiles: rendering
/// during a pinch would only be thrown away.
class ViewportSettler {
  final Duration delay;
  final void Function() onSettled;
  Timer? _t;
  ViewportSettler(this.onSettled,
      {this.delay = const Duration(milliseconds: 140)});

  bool _disposed = false;

  void poke() {
    if (_disposed) return;
    _t?.cancel();
    _t = Timer(delay, onSettled);
  }

  void dispose() {
    _disposed = true;
    _t?.cancel();
  }
}
