// Clipboard of the editor: paste of system images, text and the in-app
// clipboard, copy of selections as images, taking the context, ref and callbacks explicitly.

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/html_text.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:abelnotes/core/services/crash_logger.dart';

class ClipboardFlow {
  ClipboardFlow({
    required this.context,
    required this.ref,
    required this.insertImage,
    required this.visibleCenterPagePos,
    required this.mathPixelRatio,
  });

  final BuildContext context;
  final WidgetRef ref;
  final void Function(Uint8List bytes, String name, Offset pagePos) insertImage;
  final Offset Function(CanvasState state) visibleCenterPagePos;
  final double Function(BuildContext context) mathPixelRatio;

  /// Signature of the system-clipboard image we currently treat as "already
  /// seen" — i.e. NOT newer than the in-app clipboard. Set when we write an
  /// image to the system clipboard (our own Ctrl+C of an image) and when the
  /// user makes an internal non-image copy while a stale image happens to sit
  /// on the system clipboard. Lets Ctrl+V tell a freshly-copied EXTERNAL
  /// image (→ paste it) from a stale one (→ use the richer in-app clipboard).
  /// Fixes "copy an image, Ctrl+V pastes the old in-app text instead".
  String? _seenSystemImageSig;
  String? _seenSystemTextSig;

  /// The most recent (possibly still-running) `markSystemImageSeen()` call.
  /// A copy snapshots the system clipboard's identity ASYNCHRONOUSLY; a paste
  /// that fires right after (a user testing "does Ctrl+C/Ctrl+V work?" presses
  /// them milliseconds apart) MUST await this snapshot first — otherwise it
  /// compares the fresh system content against a STALE seen-sig, wrongly
  /// decides the external clipboard is "newer", and pastes the old image/text
  /// instead of what was just copied in-app. Awaited at the top of paste.
  Future<void>? _seenSnapshotInFlight;

  // ── Clipboard paste (system image or internal) ──

  /// Formats we accept from the system clipboard, in priority order.
  /// PNG/JPEG first because they're already universally decodable. iOS
  /// screenshots land as HEIC or TIFF on the clipboard — those fell
  /// through the old PNG-or-JPEG-only check and the paste silently did
  /// nothing on iPad. For exotic formats we transcode to PNG before
  /// storing so the asset is readable on every platform (Flutter on
  /// Windows/Linux can't decode HEIC natively).
  static const _clipboardImageFormats = <(SimpleFileFormat, String)>[
    (Formats.png, 'png'),
    (Formats.jpeg, 'jpg'),
    (Formats.heic, 'heic'),
    (Formats.heif, 'heif'),
    (Formats.tiff, 'tiff'),
    (Formats.webp, 'webp'),
    (Formats.gif, 'gif'),
    (Formats.bmp, 'bmp'),
  ];

  /// [at] anchors the paste at an explicit page position (context menu:
  /// paste where the user clicked); null → visible viewport centre.
  Future<void> pasteFromClipboard(
      {bool preferSystemImage = false, Offset? at}) async {
    // Resolve "what did the user most recently copy?" instead of blindly
    // preferring the in-app clipboard. An image on the SYSTEM clipboard wins
    // when it's genuinely newer than the in-app selection — detected by
    // comparing its signature against the last image we know about
    // (`_seenSystemImageSig`). This fixes: copy an image → Ctrl+V used to
    // paste the old in-app text because the internal clipboard short-circuit
    // always won. `preferSystemImage` (the 'Incolla immagine' menu) forces
    // the image path regardless.
    // A copy that just happened snapshots the system clipboard's identity
    // asynchronously. If the user hits Ctrl+V right behind Ctrl+C, that
    // snapshot may still be running — wait for it so the freshness compare
    // below sees the correct seen-sigs, not stale ones.
    if (_seenSnapshotInFlight != null) {
      await _seenSnapshotInFlight;
    }

    final sysImg = await _readSystemImageRaw();
    final cs = ref.read(canvasProvider);
    final hasInternal = cs != null && cs.clipboard != null;

    final systemImageIsNew =
        sysImg != null && sysImg.sig != _seenSystemImageSig;

    final useSystemImage = sysImg != null &&
        (preferSystemImage || systemImageIsNew || !hasInternal);

    if (useSystemImage) {
      // NOTE: we deliberately do NOT mark this image "seen" here — leaving
      // `_seenSystemImageSig` untouched lets a repeated Ctrl+V keep pasting
      // the same most-recently-copied image. It only flips to the in-app
      // clipboard once the user makes a fresh internal copy (which snapshots
      // the sig) or copies a different image.
      // Transcode exotic formats (HEIC/TIFF/WEBP/…) to PNG so they're
      // portable across platforms.
      Uint8List bytes = sysImg.raw;
      String fileName = 'clipboard_image.${sysImg.ext}';
      if (sysImg.ext != 'png' && sysImg.ext != 'jpg') {
        final transcoded = await _transcodeToPng(sysImg.raw);
        if (transcoded == null) {
          CrashLogger.append(
            '[Paste] failed to transcode ${sysImg.ext} from clipboard '
            '(${sysImg.raw.length} bytes)',
          );
          // Couldn't decode — fall back to the in-app clipboard below.
          if (hasInternal) _pasteInternal(at);
          return;
        }
        bytes = transcoded;
        fileName = 'clipboard_image.png';
      }
      final s = ref.read(canvasProvider);
      if (s == null || !context.mounted) return;
      insertImage(bytes, fileName, at ?? visibleCenterPagePos(s));
      return;
    }

    // ── System TEXT ── (was completely unhandled: Ctrl+V with text
    // copied from another app silently did nothing). Same freshness
    // logic as images: external text that we haven't "seen" wins over a
    // stale internal selection; with no internal clipboard, any system
    // text pastes (repeat Ctrl+V keeps working — we don't mark it seen
    // on paste, only on internal copies).
    final sysText = await _readSystemText();
    final systemTextIsNew =
        sysText != null && _textSig(sysText.plain) != _seenSystemTextSig;
    if (sysText != null && (systemTextIsNew || !hasInternal)) {
      final s = ref.read(canvasProvider);
      if (s == null || !context.mounted) return;
      final anchor = at ?? visibleCenterPagePos(s);

      // Interpret Markdown + LaTeX in the PLAIN text FIRST. A copied "$$…$$"
      // or "\[…\]" almost always ALSO carries an HTML flavour (the raw source
      // wrapped in <p>/<span> tags by the source app), but the user's intent
      // is the typeset math/markdown — NOT the literal string. So rich plain
      // text wins over HTML here; we only fall back to HTML spans when the
      // plain text isn't itself rich (e.g. bold/italic prose copied from a web
      // page, which has no markdown markers). A single all-plain block keeps
      // the legacy single-element paste; anything richer (headings, lists,
      // styled runs, display math) becomes a vertically-stacked set of
      // text + typeset-math blocks in one undo.
      final blocks = sysText.plain.trim().isEmpty
          ? const <PastedBlock>[]
          : parsePastedRich(sysText.plain);
      final plainIsRich = blocks.isNotEmpty &&
          !(blocks.length == 1 &&
              blocks.first is PastedTextBlock &&
              (blocks.first as PastedTextBlock).spans.isEmpty);
      if (plainIsRich) {
        unawaited(ref.read(canvasProvider.notifier).pasteRichBlocks(
              blocks, anchor,
              color: 0xFF000000, maxWidth: 360,
              pixelRatio: mathPixelRatio(context),
            ));
        return;
      }

      // Plain text isn't markdown/LaTeX → prefer HTML, which preserves
      // bold/italic/underline as rich spans in a single text element.
      if (sysText.html != null) {
        final rich = htmlToSpans(sysText.html!);
        if (rich != null && rich.plain.trim().isNotEmpty) {
          ref.read(canvasProvider.notifier).addTextElement(
                anchor, rich.plain,
                spans: rich.spans, color: 0xFF000000, width: 360,
              );
          return;
        }
      }
      if (sysText.plain.trim().isEmpty) {
        if (hasInternal) _pasteInternal(at);
        return;
      }
      // Plain, non-rich text → single text element.
      ref.read(canvasProvider.notifier).addTextElement(
            anchor, (blocks.first as PastedTextBlock).content,
            color: 0xFF000000, width: 360,
          );
      return;
    }

    // No (new) system image/text → use the in-app clipboard, dropping it
    // at the viewport centre so it lands where the user is looking (not
    // off the right edge of the page, the previous fixed +20,+20
    // behaviour).
    if (hasInternal) {
      _pasteInternal(at);
    }
  }

  /// Reads plain text (and HTML when present) from the system clipboard.
  /// Returns null when no usable text is available.
  Future<({String plain, String? html})?> _readSystemText() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return null;
      final reader = await clipboard.read();
      String? html;
      if (reader.canProvide(Formats.htmlText)) {
        html = await reader.readValue(Formats.htmlText);
      }
      String? plain;
      if (reader.canProvide(Formats.plainText)) {
        plain = await reader.readValue(Formats.plainText);
      }
      // Some apps put only HTML on the clipboard — derive plain from it.
      if ((plain == null || plain.isEmpty) && html != null) {
        plain = htmlToSpans(html)?.plain;
      }
      if (plain == null || plain.trim().isEmpty) return null;
      return (plain: plain, html: html);
    } catch (e) {
      CrashLogger.append('[Paste] system text read failed: $e');
      return null;
    }
  }

  /// Cheap fingerprint for clipboard text (length + rolling sample).
  String _textSig(String t) {
    int h = t.length;
    for (var i = 0; i < t.length; i += (t.length ~/ 16) + 1) {
      h = (h * 31 + t.codeUnitAt(i)) & 0x7fffffff;
    }
    return '${t.length}:$h';
  }

  void _pasteInternal(Offset? at) {
    final s = ref.read(canvasProvider);
    if (s == null) return;
    ref.read(canvasProvider.notifier).paste(at: at ?? visibleCenterPagePos(s));
  }

  /// Cheap fingerprint of clipboard image bytes — length + a few sampled
  /// bytes. Enough to tell two clipboard images apart without hashing
  /// megabytes on every copy/paste.
  String _imageSig(Uint8List b) {
    final n = b.length;
    if (n == 0) return '0';
    int h = n;
    for (final frac in const [0, 1, 2, 3, 4]) {
      final idx = ((n - 1) * frac ~/ 4);
      h = (h * 31 + b[idx]) & 0x7fffffff;
    }
    return '$n:$h';
  }

  /// Reads the first available image on the system clipboard as raw bytes
  /// (no transcode), with its extension and a signature. Returns null when
  /// no image is present. Used both to paste and to snapshot the current
  /// clipboard image's identity on internal copies.
  Future<({Uint8List raw, String ext, String sig})?>
      _readSystemImageRaw() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return null;
      final reader = await clipboard.read();
      for (final entry in _clipboardImageFormats) {
        final fmt = entry.$1;
        final ext = entry.$2;
        if (!reader.canProvide(fmt)) continue;
        final completer = Completer<Uint8List?>();
        reader.getFile(fmt, (file) async {
          try {
            completer.complete(await file.readAll());
          } catch (_) {
            completer.complete(null);
          }
        }, onError: (_) => completer.complete(null));
        final raw = await completer.future;
        if (raw == null || raw.isEmpty) continue;
        return (raw: raw, ext: ext, sig: _imageSig(raw));
      }
    } catch (e, st) {
      CrashLogger.append('[Paste] system image read failed: $e\n$st');
    }
    return null;
  }

  /// Records whatever image currently sits on the system clipboard as
  /// "seen / stale" — called after an internal NON-image copy so a later
  /// Ctrl+V doesn't resurrect a leftover external image instead of the
  /// strokes/text the user just copied. Cheap when no image is present.
  Future<void> markSystemImageSeen() {
    final future = () async {
      final r = await _readSystemImageRaw();
      _seenSystemImageSig = r?.sig;
      // Same staleness snapshot for system TEXT, so an internal copy takes
      // priority over whatever external text was left on the clipboard.
      final t = await _readSystemText();
      _seenSystemTextSig = t == null ? null : _textSig(t.plain);
    }();
    // Publish the in-flight snapshot so a paste racing right behind a copy
    // waits for it instead of reading stale seen-sigs (see field doc).
    _seenSnapshotInFlight = future;
    return future;
  }

  /// Decode [bytes] with the platform image codec and re-encode as PNG,
  /// so exotic formats (HEIC/HEIF/TIFF/WEBP/...) become portable. Returns
  /// null if the platform can't decode this format.
  Future<Uint8List?> _transcodeToPng(Uint8List bytes) async {
    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) return null;
      return pngData.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  /// Copy the current lasso selection as a screenshot to the system clipboard.
  Future<void> copySelectionAsScreenshot() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final sel = state.lassoSelection;
    final page = state.currentPage;
    if (sel == null || page == null) return;

    try {
      final bounds = sel.bounds;
      if (bounds.isEmpty) return;

      // Render at 2x for retina quality
      const scale = 2.0;
      final renderW = (bounds.width * scale).round();
      final renderH = (bounds.height * scale).round();
      if (renderW <= 0 || renderH <= 0) return;

      // Build a temporary page containing only the selected elements,
      // translated so the selection bounds start at (0,0).
      final selectedElements = page.layers.content
          .where((e) => sel.selectedIds.contains(e.id))
          .toList();

      final croppedPage = page.copyWith(
        layers: page.layers.copyWith(
          background: const BackgroundLayer(type: 'blank', color: 0xFFFFFFFF),
          content: selectedElements,
        ),
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, bounds.width * scale, bounds.height * scale));
      // White background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, bounds.width * scale, bounds.height * scale),
        Paint()..color = Colors.white,
      );
      // Scale then translate so the selection bounds map to (0,0)
      canvas.scale(scale);
      canvas.translate(-bounds.left, -bounds.top);

      // Render only the selected elements via a temporary page. Reuse the
      // live math raster cache (these equations were just on-screen, so
      // they're already rasterized) at the same screen pixel ratio.
      final engine = CanvasRenderEngine(
        pageData: croppedPage,
        zoom: 1.0,
        panOffset: Offset.zero,
        imageCache: state.imageCache,
        mathCache: ref.read(canvasProvider.notifier).mathCache,
        mathPixelRatio: mathPixelRatio(context),
      );
      // paintPage applies its own translate(offset)+scale(scale), so pass
      // the negative bounds as offset and 1.0 as scale to avoid double-transform.
      engine.paintPage(
        canvas,
        Size(croppedPage.width, croppedPage.height),
        1.0,
        Offset.zero,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(renderW, renderH);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      picture.dispose();
      if (byteData == null) return;

      final item = DataWriterItem();
      item.add(Formats.png(byteData.buffer.asUint8List()));
      await SystemClipboard.instance?.write([item]);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csSelectionCopiedAsImage), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csCopyImageError(e.toString()))),
        );
      }
    }
  }

  /// Encode an image element to PNG and push it onto the system clipboard
  /// so it can be pasted into other apps. Fire-and-forget; UI toast is
  /// shown by the caller.
  /// True when the element with [elementId] is an image (so its bytes can
  /// be mirrored to the system clipboard).
  bool selectedElementIsImage(CanvasState? state, String elementId) {
    final page = state?.currentPage;
    if (page == null) return false;
    for (final e in page.layers.content) {
      final id = e.id;
      if (id == elementId) {
        return e.maybeMap(image: (_) => true, orElse: () => false);
      }
    }
    return false;
  }

  Future<void> copyImageElementToSystemClipboard(String elementId) async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final page = state.currentPage;
    if (page == null) return;
    final element = page.layers.content.where((e) {
      return e.id ==
          elementId;
    }).firstOrNull;
    if (element == null) return;

    ImageData? imageData;
    element.map(unknown: (_) {},
      stroke: (_) {},
      text: (_) {},
      image: (i) => imageData = i.data,
      shape: (_) {},
      math: (_) {},
    );
    if (imageData == null) return;

    final uiImage = state.imageCache[imageData!.assetPath];
    if (uiImage == null) return;
    try {
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return;
      final item = DataWriterItem();
      item.add(Formats.png(pngBytes));
      await clipboard.write([item]);
      // Remember our own write so a follow-up Ctrl+V prefers the in-app
      // element (richer) over re-importing these same bytes.
      _seenSystemImageSig = _imageSig(pngBytes);
    } catch (e) {
      debugPrint('[Canvas] System clipboard image write failed: $e');
    }
  }
}
