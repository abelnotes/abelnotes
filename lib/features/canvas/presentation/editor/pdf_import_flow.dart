// PDF import of the editor: password prompt, page-range choice, rasterising
// and text-layer extraction, taking the context, ref and callbacks explicitly.

import 'dart:async';
import 'package:uuid/uuid.dart';
import 'dart:ui' as ui;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/pdf_source_renderer.dart' show pdfSourceBytes;
import 'package:abelnotes/features/canvas/data/pdf_sources.dart' show PdfSourceIndex;
import 'package:abelnotes/features/canvas/presentation/pdf_sharpener.dart';
import 'package:abelnotes/features/canvas/data/pdf_import_support.dart';
import 'package:abelnotes/features/canvas/data/pdf_text_extractor.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_password_dialog.dart';
import 'package:abelnotes/features/canvas/presentation/editor/pdf_range_dialog.dart';

class PdfImportFlow {
  PdfImportFlow({
    required this.context,
    required this.ref,
    required this.getSharpener,
    required this.reloadPdfSources,
  });

  final BuildContext context;
  final WidgetRef ref;
  final PdfSharpener? Function() getSharpener;
  final Future<void> Function() reloadPdfSources;

  /// Asks the user which pages of the PDF to import. Returns `null` if
  /// the user cancels. When the user picks "Tutte le pagine" both
  /// `start` and `end` come back null so the caller streams the entire
  /// PDF without bound checks.
  Future<PdfImportRange?> _askPdfImportRange(int estimatedPages) async {
    if (!context.mounted) return null;
    return showDialog<PdfImportRange>(
      context: context,
      builder: (ctx) => PdfRangeDialog(estimatedPages: estimatedPages),
    );
  }

  /// User-facing text for a PDF that could not be opened.
  String _pdfOpenErrorText(AppLocalizations l10n, PdfOpenFailure f) =>
      switch (f) {
        PdfOpenFailure.notPdf => l10n.qiPdfNotPdf,
        PdfOpenFailure.corrupt => l10n.qiPdfCorrupt,
        PdfOpenFailure.empty => l10n.qiPdfEmpty,
        PdfOpenFailure.unsupported => l10n.qiPdfUnsupported,
        PdfOpenFailure.passwordCancelled => l10n.qiPdfPasswordCancelled,
      };

  Future<void> insertPdf(Uint8List bytes, String name, Offset pagePos) async {
    if (!context.mounted) return;

    // Open first: an unreadable file must fail before the options dialog.
    final pdfrx.PdfDocument doc;
    try {
      doc = await openPdfForImport(
        bytes,
        askPassword: (wrong) async =>
            context.mounted ? showPdfPasswordDialog(context, wrong: wrong) : null,
      );
    } catch (e) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      debugPrint('[Canvas] PDF open failed: $e');
      final msg = e is PdfOpenException
          ? _pdfOpenErrorText(l10n, e.failure)
          : l10n.qiPdfImportFailed;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final estimated = doc.pages.length;

    // Always offer page-range selection (even for short PDFs) so the user
    // can import just the chunk they care about. The dialog falls back to
    // "all" by default so single-tap imports stay quick.
    final range = await _askPdfImportRange(estimated);
    if (range == null || !context.mounted) {
      await doc.dispose();
      return;
    }
    // 1-based inclusive bounds; null = unbounded on that side.
    final int? rangeStart = range.start;
    final int? rangeEnd = range.end;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).csPdfRasterizing), duration: const Duration(seconds: 30)),
    );

    // Single PDF engine: pdfrx (PDFium) does BOTH rasterization and embedded
    // text extraction. We deliberately do NOT use printing's `Printing.raster`
    // — it bundles a *second* PDFium and calls FPDF_DestroyLibrary after every
    // raster, which tears the library out from under pdfrx (whose init is
    // one-time) and segfaults. One engine ⇒ one global PDFium state ⇒ no
    // conflict, and the raster + text come from the exact same page geometry.
    final notifier = ref.read(canvasProvider.notifier);
    bool bulkStarted = false;
    try {
      // Adaptive DPI: big PDFs render at lower resolution so the raw pixel
      // buffers don't blow the iOS jetsam limit. 150 DPI on A4 is ~8.7 MB/page
      // of RGBA; we render → encode → free ONE page at a time to stay bounded.
      final pageCount = doc.pages.length;
      final int dpi = pageCount > 40 ? 100 : (pageCount > 15 ? 120 : 150);

      // Suppress remote pulls for the duration of the import (the per-page
      // awaits yield to the event loop; a pull mid-loop would shift
      // document.pages and misplace insertions).
      notifier.beginBulkOperation();
      bulkStarted = true;
      int processed = 0;
      final keptPages = <(String, int)>[];
      final startPage = ref.read(canvasProvider)?.currentPage;
      final startPageW = startPage?.width ?? 595.0;
      final startPageH = startPage?.height ?? 842.0;

      for (int i = 0; i < pageCount; i++) {
        if (!context.mounted) return;
        final sourcePageNumber = i + 1; // 1-based, for the range filter
        if (rangeStart != null && sourcePageNumber < rangeStart) continue;
        if (rangeEnd != null && sourcePageNumber > rangeEnd) break;

        final page = doc.pages[i];
        // Render at the displayed (rotation-applied) size in pixels.
        final bool swap = page.rotation.index.isOdd;
        final double dispWpt = swap ? page.height : page.width;
        final double dispHpt = swap ? page.width : page.height;
        // The notebook page takes the source page's shape; the raster is
        // sized from that logical size so every page costs about the same.
        final logical = pdfPageLogicalSize(dispWpt, dispHpt,
            refW: startPageW, refH: startPageH);
        final int fullW = (logical.w * dpi / 72.0).round().clamp(1, 12000);
        final int fullH = (logical.h * dpi / 72.0).round().clamp(1, 12000);

        final pdfImg = await page.render(
          fullWidth: fullW.toDouble(),
          fullHeight: fullH.toDouble(),
          backgroundColor: 0xFFFFFFFF, // opaque white page
        );
        if (!context.mounted) {
          pdfImg?.dispose();
          return;
        }
        if (pdfImg == null) continue;
        // Encode to PNG (lossless, matches the prior import output). The native
        // BGRA buffer + ui.Image are freed before the next page is rendered.
        final assetBytes = await _pdfImageToPng(pdfImg);
        pdfImg.dispose();
        if (!context.mounted) return;
        if (assetBytes == null) continue;

        // The first PDF page reuses the current page only while it is empty;
        // on top of existing content it would hide it.
        if (processed > 0 ||
            (ref.read(canvasProvider)?.currentPage?.layers.content.isNotEmpty ?? false)) {
          notifier.addPage();
        }

        // Pin the target page NOW, in the same sync block as the image
        // insert below: the text-layer extraction that follows awaits, and
        // the user can navigate to another page during a long import.
        final st = ref.read(canvasProvider);
        final targetPageFileName = st?.currentPageFileName;
        if (targetPageFileName != null &&
            (st?.currentPage?.width != logical.w ||
                st?.currentPage?.height != logical.h)) {
          notifier.setPageGeometry(targetPageFileName, logical.w, logical.h);
        }
        final imgW = logical.w;
        final imgH = logical.h;
        const insertPos = Offset.zero;
        final assetId = notifier.addImageElement(
          insertPos,
          '${name}_p${processed + 1}.png',
          assetBytes,
          imgW,
          imgH,
          locked: true,
          pdfSizePt: (w: dispWpt, h: dispHpt),
        );

        // Overlay the page's embedded text (selectable + searchable). Same
        // doc/engine as the raster, so the glyph boxes map onto the exact same
        // page geometry. Best-effort per page.
        if (assetId != null && targetPageFileName != null) {
          final layer = await PdfTextExtractor.extractPageLayer(
            doc: doc,
            pageIndex: i,
            sourceAssetPath: assetId,
            placement: PdfImagePlacement(
                offset: insertPos, width: imgW, height: imgH),
          );
          if (!context.mounted) return;
          if (layer != null) {
            notifier.setPageTextLayer(targetPageFileName, layer);
          }
        }

        if (assetId != null) keptPages.add((assetId, i));
        processed++;

        // Progress feedback for long imports so the user sees we're alive.
        final rangeTotal = (rangeStart != null && rangeEnd != null)
            ? (rangeEnd - rangeStart + 1)
            : pageCount;
        if (context.mounted && rangeTotal > 5 && processed % 5 == 0) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context).csPdfImportProgress(processed, rangeTotal)),
              duration: const Duration(seconds: 30),
            ));
        }

        // Yield so the engine can free the page's pixel buffer + PNG bytes
        // before the next allocation — keeps a large PDF import memory-bounded
        // (this is what separates "78 pages imported cleanly" from host OOM).
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      notifier.endBulkOperation();
      bulkStarted = false;
      await _keepPdfSource(doc, keptPages);
      // Decode the current page's images now that bulk import is done.
      // During import we skipped decode to keep GPU pressure bounded;
      // the user is on the last imported page and expects to see it
      // populated. Background-pull / thumbnail paths handle the rest.
      notifier.ensureCurrentPageImagesDecoded();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      if (processed == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csPdfReadFailed)),
        );
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csPdfImported(processed))),
        );
      }
    } catch (e) {
      debugPrint('[Canvas] PDF import failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).qiPdfImportFailed)),
        );
      }
    } finally {
      // Every exit path (incl. the `!mounted` returns) must re-enable remote pulls.
      if (bulkStarted) notifier.endBulkOperation();
      // Release PDFium's parse of the source PDF. Runs on every exit path
      // (including the `if (!mounted) return` guards inside the loop).
      await doc.dispose();
    }
  }

  /// Keeps the source PDF of imported pages so zooming re-renders them sharp.
  /// Best effort: without it the pages keep their PNG.
  Future<void> _keepPdfSource(
      pdfrx.PdfDocument doc, List<(String, int)> kept) async {
    final sharpener = getSharpener();
    if (sharpener == null || kept.isEmpty) return;
    try {
      final sourcePages = <int>[];
      final pages = <String, int>{};
      for (final (asset, page) in kept) {
        var at = sourcePages.indexOf(page);
        if (at < 0) {
          at = sourcePages.length;
          sourcePages.add(page);
        }
        pages[asset] = at;
      }
      final bytes = await pdfSourceBytes(doc, sourcePages);
      final id = const Uuid().v4();
      await sharpener.store.save(
          PdfSourceIndex(
              id: id,
              pdf: '$id.pdf',
              pages: pages,
              createdMs: DateTime.now().millisecondsSinceEpoch),
          bytes);
      ref.read(canvasProvider.notifier).notePdfSourcesChanged();
      await reloadPdfSources();
    } catch (e) {
      debugPrint('[Canvas] keeping the source PDF failed: $e');
    }
  }

  /// Encode a pdfrx-rendered page (BGRA8888) to PNG bytes. Returns null on
  /// failure. The intermediate ui.Image is disposed before returning.
  Future<Uint8List?> _pdfImageToPng(pdfrx.PdfImage img) async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        img.pixels,
        img.width,
        img.height,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );
      final uiImage = await completer.future;
      final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Canvas] PDF page → PNG encode failed: $e');
      return null;
    }
  }
}
