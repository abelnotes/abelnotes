import 'package:freezed_annotation/freezed_annotation.dart';

part 'ncnote_format.freezed.dart';
part 'ncnote_format.g.dart';

// ═══════════════════════════════════════════════════════════════
//  METADATA.JSON – Informazioni del taccuino
// ═══════════════════════════════════════════════════════════════

@freezed
class Chapter with _$Chapter {
  const factory Chapter({
    required String id,
    required String title,
    @Default([]) List<String> pageIds,
  }) = _Chapter;

  factory Chapter.fromJson(Map<String, dynamic> json) => _$ChapterFromJson(json);
}

@freezed
class NotebookMetadata with _$NotebookMetadata {
  const factory NotebookMetadata({
    required String id,
    required String title,
    @Default(1) int formatVersion,
    required DateTime createdAt,
    required DateTime modifiedAt,
    @Default('default') String coverStyle,
    @Default(0xFF1565C0) int coverColor, // Material Blue 800
    @Default('lined') String paperType, // blank, lined, grid, dotted
    @Default(0xFFFFFFFF) int paperColor,
    @Default(0) int pageCount,
    @Default([]) List<String> tags,
    @Default([]) List<Chapter> chapters,
    String? author,
    String? description,
  }) = _NotebookMetadata;

  factory NotebookMetadata.fromJson(Map<String, dynamic> json) =>
      _$NotebookMetadataFromJson(json);
}

// ═══════════════════════════════════════════════════════════════
//  DOCUMENT.JSON – Struttura del documento (indice pagine)
// ═══════════════════════════════════════════════════════════════

@freezed
class DocumentStructure with _$DocumentStructure {
  const factory DocumentStructure({
    required String notebookId,
    @Default(1) int formatVersion,
    required List<PageEntry> pages,
  }) = _DocumentStructure;

  factory DocumentStructure.fromJson(Map<String, dynamic> json) =>
      _$DocumentStructureFromJson(json);
}

@freezed
class PageEntry with _$PageEntry {
  const factory PageEntry({
    required String pageId,
    required int pageNumber,
    required String fileName, // es. "page_001.json"
    @Default(595.0) double width,
    @Default(842.0) double height,
    String? thumbnailFile,
    String? chapterId,
    DateTime? lastModified,
  }) = _PageEntry;

  factory PageEntry.fromJson(Map<String, dynamic> json) =>
      _$PageEntryFromJson(json);
}

// ═══════════════════════════════════════════════════════════════
//  PAGE_XXX.JSON – Dati vettoriali di una singola pagina
// ═══════════════════════════════════════════════════════════════

@freezed
class PageData with _$PageData {
  const factory PageData({
    required String pageId,
    required int pageNumber,
    required double width,
    required double height,
    required RenderingLayers layers,
    @Default([]) List<String> assetReferences,
    DateTime? createdAt,
    DateTime? modifiedAt,
    /// Selectable/searchable text overlaid on an imported PDF page. Null for
    /// ordinary pages. Populated at import time from the PDF's embedded text
    /// layer (see [PdfTextLayer]); it is overlay-only metadata and never
    /// painted, so it stays out of the z-ordered [RenderingLayers.content].
    PdfTextLayer? pdfTextLayer,
  }) = _PageData;

  factory PageData.fromJson(Map<String, dynamic> json) =>
      _$PageDataFromJson(json);
}

@freezed
class RenderingLayers with _$RenderingLayers {
  const factory RenderingLayers({
    @Default(BackgroundLayer()) BackgroundLayer background,
    @Default([]) List<ContentElement> content,
  }) = _RenderingLayers;

  factory RenderingLayers.fromJson(Map<String, dynamic> json) =>
      _$RenderingLayersFromJson(json);
}

// ── Background Layer ──

@freezed
class BackgroundLayer with _$BackgroundLayer {
  const factory BackgroundLayer({
    @Default('lined') String type, // blank, lined, grid, dotted
    @Default(0xFFFFFFFF) int color,
    @Default(30.0) double lineSpacing,
    @Default(0xFFB0B8C0) int lineColor,
    String? pdfAsset, // path in assets/ se è un PDF annotato
    @Default(0) int pdfPage, // pagina del PDF
  }) = _BackgroundLayer;

  factory BackgroundLayer.fromJson(Map<String, dynamic> json) =>
      _$BackgroundLayerFromJson(json);
}

// ── Content Elements (unione polimorfa) ──

@Freezed(unionKey: 'type')
class ContentElement with _$ContentElement {
  const factory ContentElement.stroke({
    required String id,
    required int zIndex,
    required StrokeData data,
  }) = StrokeElement;

  const factory ContentElement.text({
    required String id,
    required int zIndex,
    required TextData data,
  }) = TextElement;

  const factory ContentElement.image({
    required String id,
    required int zIndex,
    required ImageData data,
  }) = ImageElement;

  const factory ContentElement.shape({
    required String id,
    required int zIndex,
    required ShapeData data,
  }) = ShapeElement;

  const factory ContentElement.math({
    required String id,
    required int zIndex,
    required MathData data,
  }) = MathElement;

  factory ContentElement.fromJson(Map<String, dynamic> json) =>
      _$ContentElementFromJson(json);
}

// ── Stroke Data ──

@freezed
class StrokeData with _$StrokeData {
  const factory StrokeData({
    required List<StrokePoint> points,
    @Default('pen') String toolType, // pen, ballpoint, brush, highlighter
    @Default(0xFF000000) int color,
    @Default(2.0) double baseWidth,
    @Default(false) bool isHighlighter,
    @Default(1.0) double opacity,
    DateTime? timestamp,
  }) = _StrokeData;

  factory StrokeData.fromJson(Map<String, dynamic> json) =>
      _$StrokeDataFromJson(json);
}

@freezed
class StrokePoint with _$StrokePoint {
  const factory StrokePoint({
    required double x,
    required double y,
    @Default(0.5) double pressure, // 0.0 - 1.0
    @Default(0.0) double tilt, // radianti
    @Default(0) int timestamp, // millisecondi relativi dall'inizio tratto
  }) = _StrokePoint;

  factory StrokePoint.fromJson(Map<String, dynamic> json) =>
      _$StrokePointFromJson(json);
}

// ── Text Data ──

/// A styled run inside a TextData. When `spans` is non-empty it is the
/// authoritative rich representation; `TextData.content` MUST stay equal
/// to the concatenation of all span texts so older clients (and search)
/// keep working on the plain text. Null `color`/`fontSize` inherit the
/// element-level values.
@freezed
class TextSpanData with _$TextSpanData {
  const factory TextSpanData({
    required String text,
    @Default(false) bool bold,
    @Default(false) bool italic,
    @Default(false) bool underline,
    @Default(false) bool strikethrough,
    int? color,
    double? fontSize,
    /// Per-span font family override (e.g. 'monospace' for inline/code
    /// runs from pasted Markdown). Null inherits the element-level
    /// `TextData.fontFamily`.
    String? fontFamily,
  }) = _TextSpanData;

  factory TextSpanData.fromJson(Map<String, dynamic> json) =>
      _$TextSpanDataFromJson(json);
}

@freezed
class TextData with _$TextData {
  const factory TextData({
    required double x,
    required double y,
    required double width,
    required double height,
    required String content,
    @Default('sans-serif') String fontFamily,
    @Default(16.0) double fontSize,
    @Default(0xFF000000) int color,
    @Default(false) bool bold,
    @Default(false) bool italic,
    @Default('left') String alignment, // left, center, right
    /// Rich formatting runs. Empty = legacy plain text (render `content`
    /// with the element-level style). Non-empty = concat(span.text) ==
    /// content, rendered with per-span styling.
    @Default(<TextSpanData>[]) List<TextSpanData> spans,
  }) = _TextData;

  factory TextData.fromJson(Map<String, dynamic> json) =>
      _$TextDataFromJson(json);
}

// ── Math Data ──

/// A typeset LaTeX equation placed on the canvas. Only the [latex] source
/// and its style are persisted — the rendered pixels are derived at paint
/// time by rasterizing with flutter_math_fork (see MathRasterizer), so the
/// equation stays re-editable, searchable (by source), and crisp on zoom.
/// [width]/[height] are the typeset logical size measured at create/resize
/// time; the box follows the equation (it is not free-deformable).
/// [displayMode] true = block ($$…$$ / \[…\]), false = inline ($…$).
@freezed
class MathData with _$MathData {
  const factory MathData({
    required double x,
    required double y,
    required double width,
    required double height,
    required String latex,
    @Default(true) bool displayMode,
    @Default(0xFF000000) int color,
    @Default(24.0) double fontSize,
  }) = _MathData;

  factory MathData.fromJson(Map<String, dynamic> json) =>
      _$MathDataFromJson(json);
}

// ── Image Data ──

@freezed
class ImageData with _$ImageData {
  const factory ImageData({
    required double x,
    required double y,
    required double width,
    required double height,
    required String assetPath, // path relativo in assets/images/
    @Default(0.0) double rotation, // radianti
    @Default(1.0) double opacity,
    @Default(false) bool locked,
    @Default(false) bool flipHorizontal,
    String? comment,
  }) = _ImageData;

  factory ImageData.fromJson(Map<String, dynamic> json) =>
      _$ImageDataFromJson(json);
}

// ── Shape Data ──

@freezed
class ShapeData with _$ShapeData {
  const factory ShapeData({
    required String shapeType, // rectangle, circle, line, arrow, triangle
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    @Default(0xFF000000) int strokeColor,
    @Default(2.0) double strokeWidth,
    // Set when this shape was auto-recognized from a held highlighter
    // stroke, so the renderer paints it with the same translucent
    // multiply blend as highlighter ink instead of an opaque stroke.
    @Default(false) bool isHighlighter,
    int? fillColor,
    @Default(0.0) double rotation,
    // For oblique (non-cardinal) triangles: explicit absolute-page-space
    // vertices [apexX, apexY, base1X, base1Y, base2X, base2Y]. When
    // present the renderer draws this path directly; when empty it falls
    // back to the canonical bbox-relative path with `rotation` applied.
    // Cardinal triangles leave this empty (the bbox + rotation already
    // describes them exactly via the cardinal-special-case render path).
    // Stored on resize via affine bbox-to-bbox vertex remap.
    @Default(<double>[]) List<double> vertices,
  }) = _ShapeData;

  factory ShapeData.fromJson(Map<String, dynamic> json) =>
      _$ShapeDataFromJson(json);
}

// ═══════════════════════════════════════════════════════════════
//  PDF TEXT LAYER – Testo selezionabile sopra una pagina PDF
// ═══════════════════════════════════════════════════════════════

/// The selectable/searchable text recovered from an imported PDF page.
///
/// Built at import time from the PDF's *embedded* text layer (perfect glyph
/// positions, no OCR) — see the PDF import flow. It is overlay-only metadata:
/// never painted on the canvas, never part of the z-ordered content list, so
/// it does not perturb rendering, lasso, or hit-testing. The selection UI
/// draws invisible hit-testable regions from [runs] and the search service
/// indexes their text.
///
/// All coordinates in [runs] are in **page-logical points** (the same space
/// as everything else in [PageData]) — already mapped from PDF page space
/// through the raster's placement at import time. [source] distinguishes the
/// perfect embedded layer (`'embedded'`) from a future OCR fallback
/// (`'ocr'`), and [confidence] is null for embedded text.
@freezed
class PdfTextLayer with _$PdfTextLayer {
  const factory PdfTextLayer({
    /// The `assetPath` of the PDF-page image this text overlays (ties the
    /// layer back to its raster for debugging / future re-mapping).
    required String sourceAssetPath,
    @Default('embedded') String source, // 'embedded' | 'ocr'
    double? confidence, // null for embedded; mean confidence for OCR
    @Default(<PdfTextRun>[]) List<PdfTextRun> runs,
  }) = _PdfTextLayer;

  factory PdfTextLayer.fromJson(Map<String, dynamic> json) =>
      _$PdfTextLayerFromJson(json);
}

/// One contiguous run of text (a line/word fragment as the PDF groups it)
/// with its bounding box and optional per-character boxes, all in
/// page-logical points. [chars], when present, has exactly one box per UTF-16
/// code unit of [text] and powers caret-level selection; when empty the UI
/// falls back to whole-run selection.
@freezed
class PdfTextRun with _$PdfTextRun {
  const factory PdfTextRun({
    required String text,
    required double x,
    required double y,
    required double width,
    required double height,
    @Default(<PdfCharBox>[]) List<PdfCharBox> chars,
  }) = _PdfTextRun;

  factory PdfTextRun.fromJson(Map<String, dynamic> json) =>
      _$PdfTextRunFromJson(json);
}

/// Bounding box of a single character, in page-logical points.
@freezed
class PdfCharBox with _$PdfCharBox {
  const factory PdfCharBox({
    required double x,
    required double y,
    required double width,
    required double height,
  }) = _PdfCharBox;

  factory PdfCharBox.fromJson(Map<String, dynamic> json) =>
      _$PdfCharBoxFromJson(json);
}

// ═══════════════════════════════════════════════════════════════
//  SYNC METADATA – Per la gestione offline/sync
// ═══════════════════════════════════════════════════════════════

@freezed
class SyncMetadata with _$SyncMetadata {
  const factory SyncMetadata({
    required String notebookId,
    required String remotePath,
    String? localPath,
    String? etag,
    DateTime? lastSynced,
    @Default('synced') String status, // synced, modified, conflict, new
    @Default([]) List<String> dirtyPages, // pageId delle pagine modificate
  }) = _SyncMetadata;

  factory SyncMetadata.fromJson(Map<String, dynamic> json) =>
      _$SyncMetadataFromJson(json);
}
