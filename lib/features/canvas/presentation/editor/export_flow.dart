// Export (PDF, PNG, .ncnote) and share-link flow of the editor, taking the
// context, ref and a few callbacks explicitly.

import 'dart:async';
import 'package:abelnotes/core/platform/io.dart' as io;
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/nextcloud_share_service.dart' show ShareLink;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/utils/chapter_title.dart';
import 'package:abelnotes/core/providers/auth_provider.dart'
    show nextcloudShareServiceProvider;
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/services/sync_service.dart' as sync_svc;
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/features/canvas/data/pdf_export.dart';
import 'package:abelnotes/core/config/japanese_font.dart';
import 'package:abelnotes/features/canvas/data/pdf_vector_canvas.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:share_plus/share_plus.dart';
import 'package:abelnotes/ui/services/file_export.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

enum _ExportScope { currentPage, currentChapter, entireNotebook }

/// Full export selection — scope + scope-specific options.
class _ExportSelection {
  final _ExportScope scope;
  // currentChapter only: 1-based inclusive range within the chapter's pages
  final int? rangeStart;
  final int? rangeEnd;
  // entireNotebook only: insert a divider page before each chapter
  final bool chapterSeparators;

  const _ExportSelection({
    required this.scope,
    this.rangeStart,
    this.rangeEnd,
    this.chapterSeparators = false,
  });
}

/// Resolve the chapter the user means by "capitolo corrente". Prefers
/// the navigator filter ([CanvasState.activeChapterId]) but falls back
/// to the chapterId of the page currently under the viewport so the
/// "all pages" view still exports a meaningful chapter.
Chapter? resolveActiveChapter(CanvasState state) {
  String? chId = state.activeChapterId;
  if (chId == null) {
    final idx = state.currentPageIndex;
    if (idx >= 0 && idx < state.document.pages.length) {
      chId = state.document.pages[idx].chapterId;
    }
  }
  if (chId == null) return null;
  return state.metadata.chapters
      .cast<Chapter?>()
      .firstWhere((c) => c?.id == chId, orElse: () => null);
}

/// Return every [PageEntry] that belongs to [chapter], using the same
/// OR rule as the collector (PageEntry.chapterId match OR pageIds
/// membership) so the count shown in the dialog and the pages exported
/// stay in sync even after a heal pass truncated one side.
List<PageEntry> chapterPageEntries(CanvasState state, Chapter chapter) {
  final pageIds = chapter.pageIds.toSet();
  return state.document.pages
      .where((e) =>
          e.chapterId == chapter.id || pageIds.contains(e.pageId))
      .toList();
}

class ExportFlow {
  ExportFlow({
    required this.context,
    required this.ref,
    required this.currentChapterLabel,
  });

  final BuildContext context;
  final WidgetRef ref;
  final String Function(CanvasState state) currentChapterLabel;

  // ── Export ──

  /// One page for the PDF writer: vector paths when the page can be drawn
  /// that way, else the imported PDF raster itself plus a transparent
  /// annotation overlay when possible (no second rasterisation), otherwise a
  /// flat render; PDF text stays as an invisible layer.
  Future<PdfExportPage?> _pdfExportPage(
      PageData page, Map<String, ui.Image> imageCache) async {
    final runs = pdfExportRuns(page);
    final size = pdfExportPageSize(page);
    try {
      final ops = await _renderPageToVector(page, imageCache,
          sx: size.width / page.width, sy: size.height / page.height);
      return PdfExportPage(
          width: size.width, height: size.height, vector: ops, runs: runs);
    } on VectorUnsupported catch (e) {
      debugPrint('PDF export: raster fallback for page ${page.pageId}: $e');
    }
    final scale = exportScaleFor(page.width, page.height);
    final split = splitPdfBackground(page);
    final base = split == null
        ? null
        : ref.read(canvasProvider)?.assetBytes[split.assetPath];
    if (split != null && base != null) {
      Uint8List? overlay;
      if (split.overlayPage != null) {
        overlay = await _renderPageToPng(split.overlayPage!, imageCache,
            scale: scale, transparent: true);
      }
      return PdfExportPage(
          width: size.width,
          height: size.height,
          baseImage: base,
          overlayPng: overlay,
          runs: runs);
    }
    final flat = await _renderPageToPng(page, imageCache, scale: scale);
    if (flat == null) return null;
    return PdfExportPage(
        width: size.width, height: size.height, flatPng: flat, runs: runs);
  }

  /// Records a page as PDF drawing ops, mapped by [sx]/[sy] to the PDF
  /// page size. Throws [VectorUnsupported] for anything it can't draw.
  Future<List<PdfVecOp>> _renderPageToVector(
      PageData page, Map<String, ui.Image> imageCache,
      {double sx = 1, double sy = 1}) {
    final assetBytes = ref.read(canvasProvider)?.assetBytes ?? const <String, Uint8List>{};
    return _withExportCaches(page, imageCache, VectorCanvas.rasterScale,
        (images, maths) {
      final known = Map<ui.Image, Uint8List>.identity();
      images.forEach((path, img) {
        final b = assetBytes[path];
        if (b != null) known[img] = b;
      });
      final canvas = VectorCanvas(knownBytes: known, sx: sx, sy: sy);
      CanvasRenderEngine(
        pageData: page,
        zoom: 3.0, // curve interpolation density: smooth when zoomed in
        panOffset: Offset.zero,
        imageCache: images,
        mathCache: maths,
        mathPixelRatio: VectorCanvas.rasterScale,
        pathFactory: VectorPath.new,
      ).paintPage(canvas, Size(page.width, page.height), 1.0, Offset.zero);
      return canvas.finish();
    });
  }

  /// Render a single page to a PNG [Uint8List] at the given [scale].
  Future<Uint8List?> _renderPageToPng(PageData page, Map<String, ui.Image> imageCache, {double scale = 2.0, bool transparent = false}) async {
    final w = page.width;
    final h = page.height;
    final renderW = (w * scale).round();
    final renderH = (h * scale).round();
    if (renderW <= 0 || renderH <= 0) return null;
    final mathPr = scale.clamp(1.0, 4.0).toDouble();
    return _withExportCaches(page, imageCache, mathPr, (images, maths) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w * scale, h * scale));
      canvas.scale(scale);
      if (!transparent) {
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
      }

      final engine = CanvasRenderEngine(
        pageData: page,
        zoom: 1.0,
        panOffset: Offset.zero,
        imageCache: images,
        mathCache: maths,
        mathPixelRatio: mathPr,
      );
      engine.paintPage(canvas, Size(w, h), 1.0, Offset.zero);

      final picture = recorder.endRecording();
      final img = await picture.toImage(renderW, renderH);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      picture.dispose();
      return byteData?.buffer.asUint8List();
    });
  }

  /// Runs [paint] with every image of [page] decoded and every equation
  /// rasterised at [mathPr], disposing what was made here afterwards.
  Future<T> _withExportCaches<T>(
      PageData page,
      Map<String, ui.Image> imageCache,
      double mathPr,
      Future<T> Function(Map<String, ui.Image> images, Map<String, MathRaster> math) paint) async {
    // The live imageCache only holds textures for pages near the current
    // one (windowed decode + LRU eviction). Pages outside the window
    // would export with grey placeholders — decode their assets here
    // into a temporary per-page cache, disposed right after the render.
    final temp = <String, ui.Image>{};
    final assetBytes = ref.read(canvasProvider)?.assetBytes ?? const <String, Uint8List>{};
    for (final el in page.layers.content) {
      if (el is! ImageElement) continue;
      final path = el.data.assetPath;
      if (path.isEmpty || imageCache.containsKey(path) || temp.containsKey(path)) {
        continue;
      }
      final bytes = assetBytes[path];
      if (bytes == null) continue;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        temp[path] = frame.image;
      } catch (_) {
        // Corrupt asset — the engine paints its placeholder as on-canvas.
      }
    }
    final effectiveCache =
        temp.isEmpty ? imageCache : {...imageCache, ...temp};

    // Offscreen export runs paint() synchronously with a cold cache, so it
    // can't kick the async math raster + wait for a repaint. Pre-rasterize
    // every math element here (await) and inject a warm math cache, mirroring
    // the image pre-decode above. Without this, equations would export as
    // the placeholder box.
    final mathTemp = <String, MathRaster>{};
    for (final el in page.layers.content) {
      if (el is! MathElement) continue;
      final d = el.data;
      final key = mathCacheKey(
          d.latex, d.color, d.fontSize, d.displayMode, mathPr);
      if (mathTemp.containsKey(key)) continue;
      final r = await MathRasterizer.rasterize(
        latex: d.latex,
        color: Color(d.color),
        fontSize: d.fontSize,
        displayMode: d.displayMode,
        pixelRatio: mathPr,
      );
      if (r != null) mathTemp[key] = r;
    }

    try {
      return await paint(effectiveCache, mathTemp);
    } finally {
      for (final img in temp.values) {
        img.dispose();
      }
      for (final m in mathTemp.values) {
        m.image.dispose();
      }
    }
  }

  String _sanitiseForFilename(String raw) => sanitiseForFilename(raw);

  /// Build the suggested export filename. For chapter scope we append
  /// ` - <chapter title>` so exports from different chapters don't
  /// collide in the user's downloads folder.
  String _exportFilename(
      CanvasState state, _ExportScope scope, String extension) {
    final base = _sanitiseForFilename(state.metadata.title);
    switch (scope) {
      case _ExportScope.currentPage:
        return '$base - ${AppLocalizations.of(context).csPageNumber(state.currentPageIndex + 1)}.$extension';
      case _ExportScope.currentChapter:
        final ch = resolveActiveChapter(state);
        if (ch != null && ch.title.trim().isNotEmpty) {
          final chTitle = _sanitiseForFilename(ch.title);
          return '$base - $chTitle.$extension';
        }
        return '$base.$extension';
      case _ExportScope.entireNotebook:
        return '$base.$extension';
    }
  }

  /// Collect the pages to export based on user-chosen [selection].
  /// For currentChapter, applies the optional 1-based inclusive range.
  /// For entireNotebook with chapterSeparators, see [_collectExportPagesWithSeparators].
  List<PageData> _collectExportPages(
      CanvasState state, _ExportSelection selection) {
    switch (selection.scope) {
      case _ExportScope.currentPage:
        final p = state.currentPage;
        return p != null ? [p] : [];
      case _ExportScope.currentChapter:
        final chapter = resolveActiveChapter(state);
        if (chapter == null) {
          final p = state.currentPage;
          debugPrint('[Export] currentChapter fallback to currentPage: '
              'no chapter id resolvable');
          return p != null ? [p] : [];
        }
        final entries = chapterPageEntries(state, chapter);
        final all = entries
            .map((e) => state.pages[e.fileName])
            .whereType<PageData>()
            .toList();
        // Apply range slice if provided (1-based, inclusive on both ends)
        final start = (selection.rangeStart ?? 1).clamp(1, all.length);
        final end = (selection.rangeEnd ?? all.length).clamp(start, all.length);
        final result = all.sublist(start - 1, end);
        debugPrint('[Export] currentChapter ${chapter.id}: '
            'pages=${all.length}, range=$start..$end, exporting=${result.length}');
        return result;
      case _ExportScope.entireNotebook:
        return state.document.pages
            .map((e) => state.pages[e.fileName])
            .whereType<PageData>()
            .toList();
    }
  }

  /// Group every page of the notebook by chapter, in document order.
  /// Returns a list of (chapterTitle, pages) — chapterTitle is null for
  /// pages with no chapter assigned.
  List<({String? chapterTitle, List<PageData> pages})>
      _groupPagesByChapter(CanvasState state) {
    final chaptersById = {
      for (final c in state.metadata.chapters) c.id: c,
    };
    final groups = <({String? chapterTitle, List<PageData> pages})>[];
    String? currentTitle;
    List<PageData> bucket = [];
    void flush() {
      if (bucket.isNotEmpty) {
        groups.add((chapterTitle: currentTitle, pages: bucket));
      }
    }
    for (final entry in state.document.pages) {
      final pageData = state.pages[entry.fileName];
      if (pageData == null) continue;
      final chTitle = chaptersById[entry.chapterId]?.title;
      if (chTitle != currentTitle) {
        flush();
        bucket = [];
        currentTitle = chTitle;
      }
      bucket.add(pageData);
    }
    flush();
    return groups;
  }

  /// Anchor rect for the iPad share-sheet popover. SharePlus rejects a
  /// zero rect with "sharePositionOrigin must be non-zero and within
  /// coordinates of source view". Use a small box at the screen centre.
  Rect _shareOriginRect() {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height / 2;
    return Rect.fromCenter(center: Offset(cx, cy), width: 40, height: 40);
  }

  /// Save or share a file cross-platform.
  /// On iOS/macOS, uses the system share sheet (FilePicker.saveFile is broken).
  /// On other platforms, uses FilePicker.saveFile.
  Future<void> _saveOrShare(
          String fileName, Uint8List data, String mimeType) =>
      saveOrShareFile(context,
          fileName: fileName, data: data, mimeType: mimeType);

  /// Show the export scope picker, then export as PNG (single page) or
  /// a series of PNGs (multi-page → share sheet with multiple files).
  Future<void> exportAsPng() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final l10n = AppLocalizations.of(context);

    final selection = await _showExportScopeDialog(
      singlePageLabel: l10n.csExportCurrentPagePng,
      chapterLabel: l10n.csExportCurrentChapter,
      notebookLabel: l10n.csExportEntireNotebook,
    );
    if (selection == null) return;

    final pages = _collectExportPages(state, selection);
    if (pages.isEmpty) return;

    try {
      if (pages.length == 1) {
        final pngBytes = await _renderPageToPng(pages.first, state.imageCache);
        if (pngBytes == null) return;
        final fileName =
            '${_sanitiseForFilename(state.metadata.title)}_p${state.currentPageIndex + 1}.png';
        await _saveOrShare(fileName, pngBytes, 'image/png');
      } else {
        // Multiple pages → write to temp dir, share all
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csExportingPages(pages.length))),
        );
        if (kIsWeb) {
          // XFile on the web reads browser URLs, not our virtual file-system
          // paths. Download the rendered bytes directly, one file per page.
          for (var i = 0; i < pages.length; i++) {
            final bytes = await _renderPageToPng(pages[i], state.imageCache);
            if (bytes == null) continue;
            if (!context.mounted) return;
            await _saveOrShare(
                '${_sanitiseForFilename(state.metadata.title)}_p${i + 1}.png',
                bytes,
                'image/png');
          }
        } else {
          final dir = await io.Directory.systemTemp.createTemp('handwriter_export');
          final files = <XFile>[];
          for (var i = 0; i < pages.length; i++) {
            final pngBytes = await _renderPageToPng(pages[i], state.imageCache);
            if (pngBytes == null) continue;
            final f = io.File(
                '${dir.path}/${_sanitiseForFilename(state.metadata.title)}_p${i + 1}.png');
            await f.writeAsBytes(pngBytes, flush: true);
            files.add(XFile(f.path, mimeType: 'image/png'));
          }
          if (files.isNotEmpty) {
            if (io.Platform.isIOS || io.Platform.isMacOS) {
              await SharePlus.instance.share(
                ShareParams(
                  files: files,
                  subject: state.metadata.title,
                  sharePositionOrigin: _shareOriginRect(),
                ),
              );
            } else {
              // Desktop: let user pick folder, save all
              final savePath = await FilePicker.platform.getDirectoryPath(
                dialogTitle: l10n.csChooseFolderForImages(files.length),
              );
              if (savePath != null) {
                for (final xf in files) {
                  final name = xf.path.split('/').last.split('\\').last;
                  await io.File('$savePath/$name').writeAsBytes(await xf.readAsBytes());
                }
              }
            }
          }
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csPngExported(pages.length))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.csExportError(e.toString()))));
      }
    }
  }

  Future<void> exportAsPdf() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final l10n = AppLocalizations.of(context);

    final selection = await _showExportScopeDialog(
      singlePageLabel: l10n.csExportCurrentPage,
      chapterLabel: l10n.csExportCurrentChapter,
      notebookLabel: l10n.csExportEntireNotebook,
    );
    if (selection == null) return;

    // Build the actual page list. For "entireNotebook + chapterSeparators"
    // we interleave a synthetic separator page before every chapter group.
    final pagePayload = <PdfExportPage>[];
    const scale = 2.0;
    int pageCountForSnack = 0;

    if (selection.scope == _ExportScope.entireNotebook &&
        selection.chapterSeparators) {
      final groups = _groupPagesByChapter(state);
      pageCountForSnack = groups.fold(
          0, (sum, g) => sum + g.pages.length + (g.chapterTitle != null ? 1 : 0));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csGeneratingPdf(pageCountForSnack))),
        );
      }

      try {
        for (final group in groups) {
          // Use the FIRST page of the group as the size template
          final w = group.pages.isNotEmpty ? group.pages.first.width : 595.0;
          final h = group.pages.isNotEmpty ? group.pages.first.height : 842.0;
          if (group.chapterTitle != null) {
            final sepPng =
                await _renderChapterSeparatorPng(group.chapterTitle!, w, h, scale);
            if (sepPng != null) {
              pagePayload.add(PdfExportPage(
                width: w,
                height: h,
                flatPng: sepPng,
              ));
            }
          }
          for (final page in group.pages) {
            final exported = await _pdfExportPage(page, state.imageCache);
            if (exported == null) continue;
            pagePayload.add(exported);
          }
        }
        if (pagePayload.isEmpty) return;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.csPdfExportError(e.toString()))));
        }
        return;
      }
    } else {
      final pages = _collectExportPages(state, selection);
      if (pages.isEmpty) return;
      pageCountForSnack = pages.length;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csGeneratingPdf(pages.length))),
        );
      }

      for (final page in pages) {
        final exported = await _pdfExportPage(page, state.imageCache);
        if (exported == null) continue;
        pagePayload.add(exported);
      }
      if (pagePayload.isEmpty) return;
    }

    try {

      final pdfBytes = await buildPdfDocument(pagePayload);
      final fileName = _exportFilename(state, selection.scope, 'pdf');
      await _saveOrShare(fileName, pdfBytes, 'application/pdf');

      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csPdfExported(pageCountForSnack))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.csPdfExportError(e.toString()))));
      }
    }
  }

  /// Builds PDF bytes for the ENTIRE notebook, no export/share dialog.
  /// Reused by the "share as public link" flow. Returns null if there are no
  /// renderable pages. Mirrors [exportAsPdf]'s entire-notebook (no chapter
  /// separators) path, off-isolate for the actual document assembly.
  Future<Uint8List?> _buildNotebookPdfBytes(CanvasState state) async {
    final pages = state.document.pages
        .map((e) => state.pages[e.fileName])
        .whereType<PageData>()
        .toList();
    if (pages.isEmpty) return null;
    final payload = <PdfExportPage>[];
    for (final page in pages) {
      final exported = await _pdfExportPage(page, state.imageCache);
      if (exported != null) payload.add(exported);
    }
    if (payload.isEmpty) return null;
    return buildPdfDocument(payload);
  }

  /// Uploads a PDF render of the notebook to the user's Nextcloud and shows
  /// the resulting public link (copy / share). See NextcloudShareService for
  /// why this reuses the sync backend instead of our own server.
  Future<void> shareNotebookLink(CanvasState state) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final share = ref.read(nextcloudShareServiceProvider);
    if (share == null) return; // not connected — UI is gated on this anyway

    final safeName = _sanitiseForFilename(state.metadata.title);
    try {
      // Already shared? Show the existing link instantly — no re-upload, no
      // duplicate link. Reopening the share sheet is then free.
      final existing = await share.existingLink(safeName);
      if (existing != null) {
        if (!context.mounted) return;
        await _showShareLinkDialog(existing, alreadyShared: true);
        return;
      }

      messenger.showSnackBar(SnackBar(
          content: Text(l10n.csShareLinkInProgress),
          duration: const Duration(seconds: 60)));
      final pdfBytes = await _buildNotebookPdfBytes(state);
      if (pdfBytes == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      final link = await share.sharePdf(safeName: safeName, pdfBytes: pdfBytes);
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      await _showShareLinkDialog(link, alreadyShared: false);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkFailed(e.toString()))));
    }
  }

  Future<void> _showShareLinkDialog(ShareLink link,
      {required bool alreadyShared}) async {
    final l10n = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.csShareLinkTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.csShareLinkBody,
                style: TextStyle(fontSize: 13, color: p.ink2)),
            const SizedBox(height: 12),
            SelectableText(link.url,
                style: TextStyle(
                    fontSize: 13,
                    fontFamily: HwTheme.fontMono,
                    color: p.ink0)),
            const SizedBox(height: 8),
            // When the link predates recent edits, let the user push a fresh
            // PDF to the SAME link (sharePdf reuses the existing share).
            if (alreadyShared)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.csShareLinkUpdate),
                onPressed: () async {
                  Navigator.pop(dCtx);
                  await _updateSharedPdf();
                },
              ),
            // Revoke lives inside the dialog (not a footer action) so it reads
            // as the destructive, deliberate choice it is — the primary
            // actions stay copy/share.
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: HwTheme.syncConflict,
                  padding: EdgeInsets.zero),
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: Text(l10n.csRevokeLink),
              onPressed: () async {
                Navigator.pop(dCtx);
                await _revokeShareLink(link.id);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(l10n.csClose),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link.url));
              Navigator.pop(dCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.csShareLinkCopied)));
            },
            child: Text(l10n.csCopyLink),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dCtx);
              SharePlus.instance.share(ShareParams(text: link.url));
            },
            child: Text(l10n.csShare),
          ),
        ],
      ),
    );
  }

  /// Re-uploads a fresh PDF to the already-shared notebook, keeping the same
  /// public link (sharePdf reuses the existing share for the path).
  Future<void> _updateSharedPdf() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final state = ref.read(canvasProvider);
    final share = ref.read(nextcloudShareServiceProvider);
    if (state == null || share == null) return;
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.csShareLinkInProgress),
        duration: const Duration(seconds: 60)));
    try {
      final pdfBytes = await _buildNotebookPdfBytes(state);
      if (pdfBytes == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      final safeName = _sanitiseForFilename(state.metadata.title);
      final link = await share.sharePdf(safeName: safeName, pdfBytes: pdfBytes);
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkUpdated)));
      await _showShareLinkDialog(link, alreadyShared: true);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkFailed(e.toString()))));
    }
  }

  Future<void> _revokeShareLink(String shareId) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final share = ref.read(nextcloudShareServiceProvider);
    if (share == null) return;
    try {
      await share.revokeShare(shareId);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.csRevokeLinkDone)));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkFailed(e.toString()))));
    }
  }

  /// Render a "Capitolo: TITOLO" cover page for a chapter group.
  Future<Uint8List?> _renderChapterSeparatorPng(
      String chapterTitle, double pageWidth, double pageHeight, double scale) async {
    try {
      final japanese = Localizations.localeOf(context).languageCode == 'ja';
      final eyebrowText = AppLocalizations.of(context).csChapterSeparatorEyebrow;
      if (japanese || containsKana(chapterTitle)) await ensureJapaneseFont();
      final renderW = (pageWidth * scale).round();
      final renderH = (pageHeight * scale).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
          recorder, Rect.fromLTWH(0, 0, renderW.toDouble(), renderH.toDouble()));
      // Soft warm-paper background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, renderW.toDouble(), renderH.toDouble()),
        Paint()..color = const Color(0xFFFAF7F1),
      );
      // Top accent bar
      canvas.drawRect(
        Rect.fromLTWH(0, 0, renderW.toDouble(), 8 * scale),
        Paint()..color = const Color(0xFFB66744),
      );
      // "CAPITOLO" eyebrow
      final eyebrow = TextPainter(
        text: TextSpan(
          text: eyebrowText,
          style: TextStyle(
            color: const Color(0xFF6B6358),
            fontSize: 18 * scale,
            fontWeight: FontWeight.w600,
            letterSpacing: 4 * scale,
            fontFamilyFallback: japanese ? japaneseFontFallback : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      eyebrow.paint(
        canvas,
        Offset(
          (renderW - eyebrow.width) / 2,
          renderH * 0.42,
        ),
      );
      // Chapter title
      final title = TextPainter(
        text: TextSpan(
          text: chapterTitle,
          style: TextStyle(
            color: const Color(0xFF1C1916),
            fontSize: 56 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.15,
            fontFamilyFallback: japanese || containsKana(chapterTitle)
                ? japaneseFontFallback
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 3,
      )..layout(maxWidth: renderW * 0.8);
      title.paint(
        canvas,
        Offset(
          (renderW - title.width) / 2,
          renderH * 0.46,
        ),
      );
      // Decorative underline
      final underlineY = renderH * 0.46 + title.height + 24 * scale;
      final underlineW = 80 * scale;
      canvas.drawRect(
        Rect.fromLTWH(
            (renderW - underlineW) / 2, underlineY, underlineW, 3 * scale),
        Paint()..color = const Color(0xFFB66744),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(renderW, renderH);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Export] Failed to render chapter separator: $e');
      return null;
    }
  }


  /// Show a dialog for choosing export scope.
  Future<_ExportSelection?> _showExportScopeDialog({
    required String singlePageLabel,
    required String chapterLabel,
    required String notebookLabel,
  }) async {
    final state = ref.read(canvasProvider);
    final hasChapters = state != null && state.metadata.chapters.length > 1;
    final hasMultiplePages = state != null && state.document.pages.length > 1;
    final l10n = AppLocalizations.of(context);

    // If only 1 page, skip dialog
    if (!hasMultiplePages) {
      return const _ExportSelection(scope: _ExportScope.currentPage);
    }

    final scope = await showDialog<_ExportScope>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.csExport),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ExportScope.currentPage),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(singlePageLabel),
              subtitle: Text(l10n.csPageNumber(state.currentPageIndex + 1)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (hasChapters)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _ExportScope.currentChapter),
              child: ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(chapterLabel),
                subtitle: Text(currentChapterLabel(state)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ExportScope.entireNotebook),
            child: ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(notebookLabel),
              subtitle: Text(l10n.csPagesCount(state.document.pages.length)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    if (scope == null) return null;

    // Scope-specific extra prompts
    switch (scope) {
      case _ExportScope.currentPage:
        return const _ExportSelection(scope: _ExportScope.currentPage);

      case _ExportScope.currentChapter:
        // Ask range start/end if the chapter has more than 1 page
        final chapter = resolveActiveChapter(state);
        final chPagesCount = chapter == null
            ? 1
            : chapterPageEntries(state, chapter).length;
        if (chPagesCount <= 1) {
          return const _ExportSelection(scope: _ExportScope.currentChapter);
        }
        if (!context.mounted) return null;
        final range = await _promptPageRange(
          title: l10n.csExportChapterTitle,
          subtitle: chapter == null
              ? l10n.csExportCurrentChapter
              : chapterDisplayTitle(l10n, chapter.title),
          totalPages: chPagesCount,
        );
        if (range == null) return null;
        return _ExportSelection(
          scope: _ExportScope.currentChapter,
          rangeStart: range.$1,
          rangeEnd: range.$2,
        );

      case _ExportScope.entireNotebook:
        // If the notebook actually has chapters, offer the separator toggle
        if (!hasChapters) {
          return const _ExportSelection(scope: _ExportScope.entireNotebook);
        }
        if (!context.mounted) return null;
        final addSep = await _promptYesNo(
          title: l10n.csExportNotebookTitle,
          message: l10n.csChapterSeparatorQuestion,
          yesLabel: l10n.csYesWithSeparators,
          noLabel: l10n.csNoPagesOnly,
          initialValue: true,
        );
        if (addSep == null) return null;
        return _ExportSelection(
          scope: _ExportScope.entireNotebook,
          chapterSeparators: addSep,
        );
    }
  }

  /// Page-range picker dialog: returns (start, end) inclusive 1-based or null.
  Future<(int, int)?> _promptPageRange({
    required String title,
    String? subtitle,
    required int totalPages,
  }) async {
    int start = 1;
    int end = totalPages;
    final l10n = AppLocalizations.of(context);
    return showDialog<(int, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle, style: Theme.of(ctx).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                ],
                Text(l10n.csTotalPages(totalPages),
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 16),
                Text(l10n.csFromPage(start),
                    style: Theme.of(ctx).textTheme.bodyMedium),
                Slider(
                  value: start.toDouble(),
                  min: 1,
                  max: totalPages.toDouble(),
                  divisions: totalPages - 1,
                  label: '$start',
                  onChanged: (v) => setSt(() {
                    start = v.round();
                    if (start > end) end = start;
                  }),
                ),
                Text(l10n.csToPage(end),
                    style: Theme.of(ctx).textTheme.bodyMedium),
                Slider(
                  value: end.toDouble(),
                  min: 1,
                  max: totalPages.toDouble(),
                  divisions: totalPages - 1,
                  label: '$end',
                  onChanged: (v) => setSt(() {
                    end = v.round();
                    if (end < start) start = end;
                  }),
                ),
                const SizedBox(height: 8),
                Text(l10n.csWillExportPages(end - start + 1, start, end),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.csCancel)),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, (start, end)),
                child: Text(l10n.csExport),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Yes/No picker — returns true/false or null on cancel.
  Future<bool?> _promptYesNo({
    required String title,
    required String message,
    required String yesLabel,
    required String noLabel,
    bool initialValue = true,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).csCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(noLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yesLabel),
          ),
        ],
      ),
    );
  }


  /// Export bottom sheet with PDF / PNG choices.
  void showExportSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(l10n.csExport,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(l10n.csExportAsPdf),
              onTap: () {
                Navigator.of(ctx).pop();
                exportAsPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.csExportAsPng),
              onTap: () {
                Navigator.of(ctx).pop();
                exportAsPng();
              },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(l10n.csExportAsNcnote),
              subtitle: Text(l10n.csExportNcnoteSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportAsNcnote();
              },
            ),
          ],
        )),
      ),
    );
  }

  /// Native export: rebuild the .ncnote ZIP from current state and save it.
  /// Lossless — preserves vector strokes, text, shapes, images, symbols
  /// exactly as they're stored in memory.
  Future<void> _exportAsNcnote() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final l10n = AppLocalizations.of(context);
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csGeneratingNcnote)),
        );
      }
      final bytes = sync_svc.SyncService.buildPackageBytes(
        metadata: state.metadata,
        document: state.document,
        pages: state.pages,
        assets: state.assetBytes.isNotEmpty ? state.assetBytes : null,
        symbolLibraries: state.symbolLibraries.isNotEmpty
            ? state.symbolLibraries.map((l) => l.toJson()).toList()
            : null,
      );
      final fileName =
          '${_sanitiseForFilename(state.metadata.title)}${AppConfig.fileExtension}';
      await _saveOrShare(fileName, bytes, 'application/zip');
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.csNcnoteExported(
                (bytes.length / 1024).toStringAsFixed(1))),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.csNcnoteExportError(e.toString()))));
      }
    }
  }
}
