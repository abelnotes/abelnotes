import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:uuid/uuid.dart';

import 'package:abelnotes/core/providers/canvas/asset_cache.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/features/canvas/data/element_geometry.dart';
import 'package:abelnotes/features/canvas/data/text_measure.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Create, edit, move, resize and delete single text, image, shape and math
/// elements of the current page.
class ElementEditor {
  ElementEditor(this._core, this._assets);

  final CanvasCore _core;
  final AssetCache _assets;

  /// How far a new text box lets its content run before wrapping. Doubles as
  /// the legacy fixed box width every text element used to be born with.
  static const double textWrapWidth = 300;

  /// [width] is the WRAP width — how far the text may run before breaking,
  /// not the width of the resulting box. The box is then fitted to the
  /// longest line it actually produced, so a short note gets a frame around
  /// its own glyphs instead of one stretching to the wrap limit. Drag the
  /// side handles afterwards to widen it back out.
  void addTextElement(
    Offset position,
    String content, {
    double fontSize = 16,
    List<TextSpanData> spans = const [],
    int? color,
    String alignment = 'left',
    double width = textWrapWidth,
  }) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final fittedWidth = measureTextWidth(content, spans, fontSize, width);
    final fittedHeight =
        measureTextHeight(content, spans, fontSize, fittedWidth);
    // Keep a new box on the page (a tap near the right edge ran off it).
    final x = s.isScratch
        ? position.dx
        : position.dx.clamp(0.0, max(0.0, page.width - fittedWidth)).toDouble();
    final y = s.isScratch
        ? position.dy
        : position.dy.clamp(0.0, max(0.0, page.height - fittedHeight)).toDouble();

    final newElement = ContentElement.text(
      id: const Uuid().v4(),
      zIndex: _core.nextZIndex(page),
      data: TextData(
        x: x, y: y,
        width: fittedWidth,
        height: fittedHeight,
        content: content,
        spans: spans,
        fontSize: fontSize,
        color: color ?? s.toolSettings.color,
        alignment: alignment,
      ),
    );

    final updatedPage = _core.pageWithNewElement(page, newElement);
    _core.commitPageEdit(s, fileName, updatedPage, undoOf: page);
  }

  /// Replace content/style of an existing TextElement (rich editor's
  /// "Modifica testo"). Keeps position and width; height re-measured to
  /// fit the new content. No-op when the id isn't on the current page.
  void updateTextElement(
    String elementId, {
    required String content,
    required List<TextSpanData> spans,
    required double fontSize,
    required int color,
    required String alignment,
  }) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final idx = page.layers.content.indexWhere(
        (e) => e is TextElement && e.id == elementId);
    if (idx < 0) return;
    final old = page.layers.content[idx] as TextElement;


    // Does this box still have the width we gave it, or one the user set?
    // Compare against what its OLD content measured to: if they agree the box
    // is still auto-fitted and follows the new content. Any other width —
    // dragged wider OR narrower — is a deliberate wrap setting and becomes
    // the wrap limit instead of being overwritten.
    //
    // A box sitting at exactly [_kTextWrapWidth] also counts as auto: that is
    // the fixed width every box was born with before they were fitted, so
    // editing an old note is what finally trims its oversized frame.
    final oldFitted = measureTextWidth(
        old.data.content, old.data.spans, old.data.fontSize, textWrapWidth);
    final isAutoWidth = (old.data.width - oldFitted).abs() <= 1.0 ||
        (old.data.width - textWrapWidth).abs() <= 0.5;
    final newWidth = isAutoWidth
        ? measureTextWidth(content, spans, fontSize, textWrapWidth)
        : old.data.width;

    final newData = old.data.copyWith(
      content: content,
      spans: spans,
      fontSize: fontSize,
      color: color,
      alignment: alignment,
      // Element-level bold/italic are legacy whole-block flags; the
      // editor baked them into spans on load, so clear them here.
      bold: false,
      italic: false,
      // Auto-fit the box to the new content, but keep a width the user had
      // widened past its content — that width is a deliberate wrap setting,
      // and re-hugging it on every edit would undo their layout. Same test
      // the height uses below: a box still sitting at its own measured size
      // was never resized by hand, so it is ours to re-fit.
      width: newWidth,
      // Auto-fit the box to the new content, but keep a height the user had
      // previously extended past the content (a fixed/taller frame) so editing
      // text doesn't collapse it back to hugging the text.
      height: () {
        final measured =
            measureTextHeight(content, spans, fontSize, newWidth);
        final oldMeasured = measureTextHeight(
            old.data.content, old.data.spans, old.data.fontSize, old.data.width);
        final wasExtended = old.data.height > oldMeasured + 1.0;
        return wasExtended ? max(old.data.height, measured) : measured;
      }(),
    );
    final newContent = List<ContentElement>.from(page.layers.content);
    newContent[idx] = old.copyWith(data: newData);

    final updatedPage = _core.pageWithContent(page, newContent);
    _core.commitPageEdit(s, fileName, updatedPage, undoOf: page);
  }

  /// Smart resize for a TEXT element (GoodNotes/Keynote semantics).
  ///
  /// - Side handles → pass [width] only: re-wrap to the new width and
  ///   auto-fit height. fontSize untouched.
  /// - Corner handles → pass [fontScale] (uniform drag factor) AND the
  ///   proportionally-scaled [width]: multiply the element fontSize and every
  ///   per-span fontSize override by [fontScale], then auto-fit height.
  ///
  /// [topLeft] repositions the box (a left/top-edge drag moves the corner).
  /// PRESERVES spans, fontFamily, color, bold, italic, alignment, content —
  /// mutates via copyWith, never rebuilding TextData. No undo push here: the
  /// gesture already pushed one on drag-start (matches resizeElement).
  void resizeTextElement(
    String elementId, {
    double? width,
    double? height,
    double? fontScale,
    Offset? topLeft,
  }) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final idx = page.layers.content
        .indexWhere((e) => e is TextElement && e.id == elementId);
    if (idx < 0) return;
    final old = page.layers.content[idx] as TextElement;
    final d = old.data;

    final newWidth = (width ?? d.width).clamp(20.0, 100000.0).toDouble();

    var newFontSize = d.fontSize;
    var newSpans = d.spans;
    if (fontScale != null && fontScale > 0 && (fontScale - 1.0).abs() > 1e-6) {
      newFontSize = (d.fontSize * fontScale).clamp(6.0, 200.0).toDouble();
      if (d.spans.isNotEmpty) {
        newSpans = d.spans
            .map((sp) => sp.fontSize == null
                ? sp
                : sp.copyWith(
                    fontSize: (sp.fontSize! * fontScale).clamp(6.0, 200.0)))
            .toList();
      }
    }

    // The text box is a frame (see [measureTextHeight] for the content-fit
    // measurement). `measured` is the height the content actually needs at the
    // new width/font; the box may be TALLER (the user dragged a height handle)
    // but never shorter — that would clip text.
    final measured =
        measureTextHeight(d.content, newSpans, newFontSize, newWidth);
    final double newHeight;
    if (height != null) {
      // Explicit frame height from a height/corner handle drag.
      newHeight = max(height, measured);
    } else {
      // Width or font change with no explicit height: keep a box the user had
      // previously extended past its content, otherwise auto-fit to content.
      final oldMeasured =
          measureTextHeight(d.content, d.spans, d.fontSize, d.width);
      final wasExtended = d.height > oldMeasured + 1.0;
      newHeight = wasExtended ? max(d.height, measured) : measured;
    }

    final newData = d.copyWith(
      x: topLeft?.dx ?? d.x,
      y: topLeft?.dy ?? d.y,
      width: newWidth,
      height: newHeight,
      fontSize: newFontSize,
      spans: newSpans,
    );

    final newContent = List<ContentElement>.from(page.layers.content);
    newContent[idx] = old.copyWith(data: newData);

    final updatedPage = _core.pageWithContent(page, newContent);
    _core.commitPageEdit(s, fileName, updatedPage, history: false);
  }

  void moveElement(String elementId, Offset delta) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    // No undo push here: startDragElement pushed one at drag start.
    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (id != elementId) return element;
      return translateElement(element, delta);
    }).toList();

    final updatedPage = _core.pageWithContent(page, updatedContent);

    _core.commitPageEdit(s, fileName, updatedPage, history: false);
  }

  /// Call this before starting a drag to push undo state once
  void startDragElement(String elementId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _core.pushUndo(s, fileName, page);
    _core.state = s.copyWith(undoStack: undoStack, redoStack: []);
  }

  void resizeElement(String elementId, Rect newBounds) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (id != elementId) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e as ContentElement, // can't resize strokes this way
        // Text resize from the smart-resize flow goes through
        // resizeTextElement; this arm is the generic fallback. copyWith
        // preserves spans/fontFamily, and height is re-fit to the new
        // width rather than free-stretched (auto-fit owns height).
        text: (e) => ContentElement.text(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x: newBounds.left, y: newBounds.top,
            width: newBounds.width,
            height: measureTextHeight(
                e.data.content, e.data.spans, e.data.fontSize, newBounds.width),
          ),
        ),
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x: newBounds.left, y: newBounds.top,
            width: newBounds.width, height: newBounds.height,
          ),
        ),
        shape: (e) {
          // Triangles with explicit vertices: remap each vertex via the
          // bbox→bbox affine so the shape stretches/translates with the
          // new bbox while preserving relative geometry. Without this,
          // resize would change the bbox but the absolute-coord vertices
          // would stay frozen at the original position, producing a
          // mismatched shape.
          List<double> remappedVertices = e.data.vertices;
          if (e.data.vertices.length == 6) {
            final oldL = min(e.data.x1, e.data.x2);
            final oldT = min(e.data.y1, e.data.y2);
            final oldR = max(e.data.x1, e.data.x2);
            final oldB = max(e.data.y1, e.data.y2);
            final oldW = oldR - oldL;
            final oldH = oldB - oldT;
            final newW = newBounds.width;
            final newH = newBounds.height;
            double mapX(double x) => oldW <= 0
                ? newBounds.left
                : newBounds.left + (x - oldL) / oldW * newW;
            double mapY(double y) => oldH <= 0
                ? newBounds.top
                : newBounds.top + (y - oldT) / oldH * newH;
            final v = e.data.vertices;
            remappedVertices = [
              mapX(v[0]), mapY(v[1]),
              mapX(v[2]), mapY(v[3]),
              mapX(v[4]), mapY(v[5]),
            ];
          }
          return ContentElement.shape(
            id: e.id, zIndex: e.zIndex,
            data: e.data.copyWith(
              x1: newBounds.left, y1: newBounds.top,
              x2: newBounds.right, y2: newBounds.bottom,
              vertices: remappedVertices,
            ),
          );
        },
        math: (e) {
          final s = e.data.width <= 0 ? 1.0 : newBounds.width / e.data.width;
          return ContentElement.math(
            id: e.id, zIndex: e.zIndex,
            data: e.data.copyWith(
              x: newBounds.left, y: newBounds.top,
              width: newBounds.width, height: newBounds.height,
              fontSize: (e.data.fontSize * s).clamp(6.0, 200.0),
            ),
          );
        },
      );
    }).toList();

    final updatedPage = _core.pageWithContent(page, updatedContent);

    _core.commitPageEdit(s, fileName, updatedPage, history: false);
  }

  void rotateElement(String elementId, double deltaAngle) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (id != elementId) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(rotation: e.data.rotation + deltaAngle),
        ),
        shape: (e) {
          // Vertex triangles ignore the rotation field (render path uses
          // the absolute vertices). Apply the rotation directly to the
          // vertices around the bbox center so the visible shape rotates.
          final cx = (e.data.x1 + e.data.x2) / 2;
          final cy = (e.data.y1 + e.data.y2) / 2;
          final cosA = cos(deltaAngle);
          final sinA = sin(deltaAngle);
          final newVertices = transformVertices(e.data.vertices, (p) {
            final dx = p.dx - cx;
            final dy = p.dy - cy;
            return Offset(cx + dx * cosA - dy * sinA,
                          cy + dx * sinA + dy * cosA);
          });
          return ContentElement.shape(
            id: e.id, zIndex: e.zIndex,
            data: e.data.copyWith(
              rotation: e.data.rotation + deltaAngle,
              vertices: newVertices,
            ),
          );
        },
        math: (e) => e as ContentElement,
      );
    }).toList();

    final updatedPage = _core.pageWithContent(page, updatedContent);

    _core.commitPageEdit(s, fileName, updatedPage, history: false);
  }

  void deleteElement(String elementId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final filteredContent = page.layers.content.where((element) {
      final id = element.id;
      return id != elementId;
    }).toList();
    // Nothing to delete: no undo step, redo stays.
    if (filteredContent.length == page.layers.content.length) return;

    final updatedPage = _core.pageWithContent(page, filteredContent);

    _core.commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(clearSelectedElement: true));
  }

  void bringToFront(String elementId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final content = List<ContentElement>.from(page.layers.content);
    final idx = content.indexWhere((e) =>
        e.id == elementId);
    if (idx < 0 || idx == content.length - 1) return;
    final element = content.removeAt(idx);
    // Give it a zIndex higher than all others
    final maxZ = content.fold<int>(0, (m, e) =>
        max(m, e.zIndex));
    final updated = element.map(unknown: (u) => u.copyWith(zIndex: maxZ + 1),
      stroke: (e) => ContentElement.stroke(id: e.id, zIndex: maxZ + 1, data: e.data),
      text: (e) => ContentElement.text(id: e.id, zIndex: maxZ + 1, data: e.data),
      image: (e) => ContentElement.image(id: e.id, zIndex: maxZ + 1, data: e.data),
      shape: (e) => ContentElement.shape(id: e.id, zIndex: maxZ + 1, data: e.data),
      math: (e) => ContentElement.math(id: e.id, zIndex: maxZ + 1, data: e.data),
    );
    content.add(updated);

    _core.commitPageEdit(s, fileName, _core.pageWithContent(page, content), undoOf: page);
  }

  void sendToBack(String elementId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final content = List<ContentElement>.from(page.layers.content);
    final idx = content.indexWhere((e) =>
        e.id == elementId);
    if (idx <= 0) return;
    final element = content.removeAt(idx);
    // Give it a zIndex lower than all others
    final minZ = content.fold<int>(999999, (m, e) =>
        min(m, e.zIndex));
    final updated = element.map(unknown: (u) => u.copyWith(zIndex: minZ - 1),
      stroke: (e) => ContentElement.stroke(id: e.id, zIndex: minZ - 1, data: e.data),
      text: (e) => ContentElement.text(id: e.id, zIndex: minZ - 1, data: e.data),
      image: (e) => ContentElement.image(id: e.id, zIndex: minZ - 1, data: e.data),
      shape: (e) => ContentElement.shape(id: e.id, zIndex: minZ - 1, data: e.data),
      math: (e) => ContentElement.math(id: e.id, zIndex: minZ - 1, data: e.data),
    );
    content.insert(0, updated);

    _core.commitPageEdit(s, fileName, _core.pageWithContent(page, content), undoOf: page);
  }

  void toggleImageLock(String elementId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (id != elementId) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(locked: !e.data.locked),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    _core.commitPageEdit(s, fileName, _core.pageWithContent(page, updatedContent));
  }

  /// Toggles horizontal flip on an image element.
  void flipImageElement(String elementId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (id != elementId) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(flipHorizontal: !e.data.flipHorizontal),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    _core.commitPageEdit(s, fileName, _core.pageWithContent(page, updatedContent));
  }

  void setImageComment(String elementId, String? comment) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (id != elementId) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(comment: comment),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    _core.commitPageEdit(s, fileName, _core.pageWithContent(page, updatedContent));
  }

  /// Returns the asset id the image was stored under (`null` if no current
  /// page). PDF import uses the returned id to tie an extracted text layer
  /// back to its raster (see [setPageTextLayer]).
  String? addImageElement(Offset position, String fileName, Uint8List bytes, double width, double height, {bool locked = false, ({double w, double h})? pdfSizePt}) {
    if (_core.state == null) return null;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return null;
    final pageFileName = s.currentPageFileName;
    // Content-dedup: reuse an existing identical-bytes asset instead of
    // minting a fresh UUID. PDF (re-)import and page-duplicate otherwise store
    // the same page render under a new id each time, bloating the notebook
    // (observed: 62 duplicate groups / ~19 MB in one notebook).
    final dupId = _core.findIdenticalAsset(bytes, s.assetBytes);
    final assetId = dupId ?? '${const Uuid().v4()}_$fileName';

    final newElement = ContentElement.image(
      id: const Uuid().v4(),
      zIndex: _core.nextZIndex(page),
      data: ImageData(
        x: position.dx, y: position.dy,
        width: width, height: height,
        assetPath: assetId,
        locked: locked,
        pdfWidthPt: pdfSizePt?.w,
        pdfHeightPt: pdfSizePt?.h,
      ),
    );

    final updatedPage = _core.pageWithNewElement(page, newElement).copyWith(
      assetReferences: [...page.assetReferences, assetId],
    );
    // Store raw bytes for persistence and decode for rendering. When we reused
    // an existing asset (dupId != null) the bytes are already present and
    // already uploaded — only register/mark-dirty genuinely new content.
    final newAssetBytes = Map<String, Uint8List>.from(s.assetBytes);
    if (dupId == null) {
      newAssetBytes[assetId] = bytes;
      (_core.assetsByLength[bytes.length] ??= []).add(assetId);
    }
    // Skip eager decode during bulk operations (PDF import). Each
    // decoded `ui.Image` lives on the GPU at ~3-5 MB; eagerly
    // decoding 78 PDF pages while importing was the OOM that
    // crashed the host. The thumbnail / current-page render path
    // calls `ensureAssetDecodedForThumbnail` lazily for what's
    // actually visible, so deferring is correct — the user is on
    // ONE page during the import, and only that page's image needs
    // to be decoded.
    if (!_core.bulkOperationInProgress) {
      _assets.decodeAndCache(assetId, newAssetBytes[assetId] ?? bytes);
    }
    if (dupId == null) _core.markAssetDirty(assetId);

    _core.commitPageEdit(s, pageFileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(
              assetBytes: newAssetBytes,
              selectedElementId: newElement.id,
              currentTool: CanvasTool.lasso,
            ));
    return assetId;
  }

  /// Crop an image element using a normalized crop rect (0..1).
  /// Creates a new cropped image from the original bytes.
  Future<void> cropImageElement(String elementId, Rect normalizedCrop) async {
    if (_core.state == null) return;
    final s0 = _core.state!;
    final page0 = s0.currentPage;
    if (page0 == null) return;
    // Encoding awaits: the page is re-read by this name afterwards.
    final fileName = s0.currentPageFileName;

    // Find the image element
    ImageData? imgData;
    for (final el in page0.layers.content) {
      el.map(unknown: (_) {},
        stroke: (_) {},
        text: (_) {},
        image: (i) { if (i.id == elementId) imgData = i.data; },
        shape: (_) {},
        math: (_) {},
      );
    }
    if (imgData == null) return;

    final cachedImage = s0.imageCache[imgData!.assetPath];
    if (cachedImage == null) return;

    // Crop the image using a PictureRecorder
    final srcW = cachedImage.width.toDouble();
    final srcH = cachedImage.height.toDouble();
    final cropSrc = Rect.fromLTRB(
      normalizedCrop.left * srcW,
      normalizedCrop.top * srcH,
      normalizedCrop.right * srcW,
      normalizedCrop.bottom * srcH,
    );
    final cropW = cropSrc.width.toInt();
    final cropH = cropSrc.height.toInt();
    if (cropW < 1 || cropH < 1) return;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      cachedImage,
      cropSrc,
      Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    Image croppedImage;
    Uint8List croppedBytes;
    try {
      croppedImage = await picture.toImage(cropW, cropH);
      // Encode the cropped image to PNG bytes
      final byteData = await croppedImage.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        croppedImage.dispose();
        return;
      }
      croppedBytes = Uint8List.fromList(byteData.buffer.asUint8List());
    } finally {
      // Picture holds GPU/CPU display-list memory; release ASAP.
      picture.dispose();
    }

    // Encoding awaited: re-read by file name, as in updateMathLatex. Skip when
    // the element is gone or its picture changed meanwhile.
    if (_core.isDisposed) {
      croppedImage.dispose();
      return;
    }
    final s = _core.state;
    final page = s?.pages[fileName];
    final current = page?.layers.content
        .whereType<ImageElement>()
        .where((e) => e.id == elementId)
        .firstOrNull;
    if (s == null ||
        page == null ||
        current == null ||
        current.data.assetPath != imgData!.assetPath) {
      croppedImage.dispose();
      return;
    }

    final newAssetId = '${const Uuid().v4()}_cropped.png';

    // Update the image element dimensions (scale on page proportionally)
    final scaleX = normalizedCrop.width;
    final scaleY = normalizedCrop.height;
    final newPageW = current.data.width * scaleX;
    final newPageH = current.data.height * scaleY;
    final newX = current.data.x + current.data.width * normalizedCrop.left;
    final newY = current.data.y + current.data.height * normalizedCrop.top;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (id != elementId) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: ImageData(
            x: newX, y: newY,
            width: newPageW, height: newPageH,
            assetPath: newAssetId,
            rotation: e.data.rotation,
            opacity: e.data.opacity,
            locked: e.data.locked, comment: e.data.comment,
          ),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    final updatedPage = _core.pageWithContent(page, updatedContent);

    // Update caches
    final newCache = Map<String, Image>.from(s.imageCache);
    // Defensive: if a previous image happened to be keyed under the new
    // (unique UUID) assetId — shouldn't happen but we've seen IDs collide
    // after aborted crop+undo sequences — dispose it before replacing.
    final previousAtNewId = newCache[newAssetId];
    if (previousAtNewId != null && !identical(previousAtNewId, croppedImage)) {
      previousAtNewId.dispose();
    }
    newCache[newAssetId] = croppedImage;
    final newAssets = Map<String, Uint8List>.from(s.assetBytes);
    newAssets[newAssetId] = croppedBytes;
    _core.markAssetDirty(newAssetId);

    _core.commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(imageCache: newCache, assetBytes: newAssets));
    _assets.imageCacheVersion.value++;
  }

  /// Replaces the LaTeX of math element [elementId], re-measured and kept
  /// centred where it was. One undo entry.
  Future<void> updateMathLatex(String elementId, String latex) async {
    if (latex.trim().isEmpty) return;
    var s = _core.state;
    var page = s?.currentPage;
    if (s == null || page == null) return;
    final fileName = s.currentPageFileName;
    final old = page.layers.content
        .whereType<MathElement>()
        .where((e) => e.id == elementId)
        .firstOrNull;
    if (old == null || old.data.latex == latex) return;

    final d = old.data;
    final size = await _assets.measureMath(latex,
        colorArgb: d.color, fontSize: d.fontSize, displayMode: d.displayMode);
    // A resize stretches the box, not fontSize: carry that stretch over.
    final oldSize = await _assets.measureMath(d.latex,
        colorArgb: d.color, fontSize: d.fontSize, displayMode: d.displayMode);
    final sx = (oldSize != null && oldSize.width > 0) ? d.width / oldSize.width : 1.0;
    final sy = (oldSize != null && oldSize.height > 0) ? d.height / oldSize.height : 1.0;

    // measureMath awaited: re-read by file name, as in replaceInkWithMath.
    if (_core.isDisposed) return;
    s = _core.state;
    page = s?.pages[fileName];
    if (s == null || page == null) return;
    final idx = page.layers.content
        .indexWhere((e) => e is MathElement && e.id == elementId);
    if (idx < 0) return;
    final current = page.layers.content[idx] as MathElement;

    final width = size != null ? size.width * sx : current.data.width;
    final height = size != null ? size.height * sy : current.data.height;
    final cx = current.data.x + current.data.width / 2;
    final cy = current.data.y + current.data.height / 2;
    final newContent = List<ContentElement>.from(page.layers.content);
    newContent[idx] = current.copyWith(
      data: current.data.copyWith(
        latex: latex,
        x: cx - width / 2,
        y: cy - height / 2,
        width: width,
        height: height,
      ),
    );
    final updatedPage = _core.pageWithContent(page, newContent);
    _core.commitPageEdit(s, fileName, updatedPage, undoOf: page);
  }
}
