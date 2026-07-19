// ═══════════════════════════════════════════════════════════════
//  canvas_state.dart
//
//  All enums, helper functions, and immutable data-model classes
//  that make up the canvas state tree.  Extracted from the
//  monolithic canvas_provider.dart so that UI files, conflict
//  screens, etc. can import a lighter file without pulling in the
//  full CanvasNotifier.
//
//  canvas_provider.dart re-exports this file so all existing
//  `import 'canvas_provider.dart'` statements continue to work.
// ═══════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

// ═══════════════════════════════════════════════════════════════
//  ENUMS & CONSTANTS
// ═══════════════════════════════════════════════════════════════

enum CanvasTool {
  pen,
  ballpoint,
  brush,
  calligraphy,
  highlighter,
  eraserStandard,
  eraserStroke,
  lasso,
  text,
  shape,
  image,
  pan,
  /// Presentation laser pointer — strokes fade out and are NEVER
  /// committed to the page. Useful while presenting a notebook.
  laser,
}

enum EraserSize { small, medium, large }

double eraserSizeToRadius(EraserSize size) {
  switch (size) {
    case EraserSize.small: return 4.0;
    case EraserSize.medium: return 8.0;
    case EraserSize.large: return 20.0;
  }
}

enum PaperType { blank, linedNarrow, linedWide, grid, dotted, cornell, isometric, music }

String paperTypeToString(PaperType type) {
  switch (type) {
    case PaperType.blank: return 'blank';
    case PaperType.linedNarrow: return 'lined_narrow';
    case PaperType.linedWide: return 'lined_wide';
    case PaperType.grid: return 'grid';
    case PaperType.dotted: return 'dotted';
    case PaperType.cornell: return 'cornell';
    case PaperType.isometric: return 'isometric';
    case PaperType.music: return 'music';
  }
}

PaperType paperTypeFromString(String s) {
  switch (s) {
    case 'lined_narrow': return PaperType.linedNarrow;
    case 'lined_wide': return PaperType.linedWide;
    case 'lined': return PaperType.linedWide;
    case 'grid': return PaperType.grid;
    case 'dotted': return PaperType.dotted;
    case 'cornell': return PaperType.cornell;
    case 'isometric': return PaperType.isometric;
    case 'music': return PaperType.music;
    default: return PaperType.blank;
  }
}

double paperTypeLineSpacing(PaperType type) {
  switch (type) {
    case PaperType.blank: return 0;
    case PaperType.linedNarrow: return 20.0;
    case PaperType.linedWide: return 35.0;
    case PaperType.grid: return 25.0;
    case PaperType.dotted: return 25.0;
    case PaperType.cornell: return 25.0;
    case PaperType.isometric: return 30.0;
    case PaperType.music: return 8.0;
  }
}

// ═══════════════════════════════════════════════════════════════
//  TOOL SETTINGS
// ═══════════════════════════════════════════════════════════════

/// One slot of the OneNote-style preset rail. Each preset captures the
/// pen-class tool + colour + thickness so the user can flip between
/// 3 of their most-used "pens" with a single tap. Persisted in
/// `AppSettings.toolPresets`, keyed per tool, so the slots survive app
/// restarts and pen/highlighter/etc. each keep their own independent 3.
class PenPreset {
  final CanvasTool tool;
  final int color;
  final double strokeWidth;
  final double opacity;

  const PenPreset({
    required this.tool,
    required this.color,
    required this.strokeWidth,
    this.opacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'color': color,
        'strokeWidth': strokeWidth,
        'opacity': opacity,
      };

  static PenPreset? fromJson(Map<String, dynamic> json) {
    final toolName = json['tool'] as String?;
    if (toolName == null) return null;
    final tool = CanvasTool.values.firstWhere(
      (t) => t.name == toolName,
      orElse: () => CanvasTool.pen,
    );
    return PenPreset(
      tool: tool,
      color: json['color'] as int? ?? 0xFF000000,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.5,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class ToolSettings {
  final int color;
  final double strokeWidth;
  final double opacity;
  final String shapeType;
  final EraserSize eraserSize;
  final bool shapeRecognition;

  const ToolSettings({
    this.color = 0xFF000000,
    this.strokeWidth = 1.5,
    this.opacity = 1.0,
    this.shapeType = 'rectangle',
    this.eraserSize = EraserSize.medium,
    this.shapeRecognition = true,
  });

  ToolSettings copyWith({
    int? color,
    double? strokeWidth,
    double? opacity,
    String? shapeType,
    EraserSize? eraserSize,
    bool? shapeRecognition,
  }) =>
      ToolSettings(
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        shapeType: shapeType ?? this.shapeType,
        eraserSize: eraserSize ?? this.eraserSize,
        shapeRecognition: shapeRecognition ?? this.shapeRecognition,
      );
}

// ═══════════════════════════════════════════════════════════════
//  LASSO SELECTION
// ═══════════════════════════════════════════════════════════════

class LassoSelection {
  final List<String> selectedIds;
  final Rect bounds;
  final Offset dragOffset;
  final double rotation;
  final double scale;

  const LassoSelection({
    required this.selectedIds,
    required this.bounds,
    this.dragOffset = Offset.zero,
    this.rotation = 0.0,
    this.scale = 1.0,
  });

  LassoSelection copyWith({
    List<String>? selectedIds,
    Rect? bounds,
    Offset? dragOffset,
    double? rotation,
    double? scale,
  }) => LassoSelection(
    selectedIds: selectedIds ?? this.selectedIds,
    bounds: bounds ?? this.bounds,
    dragOffset: dragOffset ?? this.dragOffset,
    rotation: rotation ?? this.rotation,
    scale: scale ?? this.scale,
  );
}

// ═══════════════════════════════════════════════════════════════
//  CLIPBOARD & SYMBOLS
// ═══════════════════════════════════════════════════════════════

class CanvasClipboard {
  final List<ContentElement> elements;
  final Rect bounds;

  /// Bytes of every asset referenced by [elements] (image / PDF-page
  /// rasters). Carried in the clipboard so a CROSS-notebook paste can
  /// materialize them in the destination notebook — the destination has no
  /// copy of the source notebook's asset store, and without the bytes the
  /// pasted element would point at an asset id that exists nowhere,
  /// leaving a permanently broken reference.
  final Map<String, Uint8List> assets;

  const CanvasClipboard({
    required this.elements,
    required this.bounds,
    this.assets = const {},
  });
}

class ReusableSymbol {
  final String id;
  final String name;
  final List<ContentElement> elements;
  final Rect bounds;
  final DateTime createdAt;
  const ReusableSymbol({
    required this.id,
    required this.name,
    required this.elements,
    required this.bounds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'elements': elements.map((e) => e.toJson()).toList(),
    'bounds': {'left': bounds.left, 'top': bounds.top, 'right': bounds.right, 'bottom': bounds.bottom},
    'createdAt': createdAt.toIso8601String(),
  };

  factory ReusableSymbol.fromJson(Map<String, dynamic> json) => ReusableSymbol(
    id: json['id'] as String,
    name: json['name'] as String,
    elements: (json['elements'] as List).map((e) => ContentElement.fromJson(e as Map<String, dynamic>)).toList(),
    bounds: Rect.fromLTRB(
      (json['bounds']['left'] as num).toDouble(),
      (json['bounds']['top'] as num).toDouble(),
      (json['bounds']['right'] as num).toDouble(),
      (json['bounds']['bottom'] as num).toDouble(),
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class SymbolLibrary {
  final String id;
  final String name;
  final List<ReusableSymbol> symbols;
  const SymbolLibrary({
    required this.id,
    required this.name,
    this.symbols = const [],
  });
  SymbolLibrary copyWith({String? name, List<ReusableSymbol>? symbols}) =>
      SymbolLibrary(id: id, name: name ?? this.name, symbols: symbols ?? this.symbols);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'symbols': symbols.map((s) => s.toJson()).toList(),
  };

  factory SymbolLibrary.fromJson(Map<String, dynamic> json) => SymbolLibrary(
    id: json['id'] as String,
    name: json['name'] as String,
    symbols: (json['symbols'] as List?)?.map((s) => ReusableSymbol.fromJson(s as Map<String, dynamic>)).toList() ?? [],
  );
}

// ═══════════════════════════════════════════════════════════════
//  PENDING REMOTE CHANGES — shown to user for accept/dismiss
// ═══════════════════════════════════════════════════════════════

enum PageChangeType { modified, added, deleted }

class PageChangeDetail {
  final String fileName;
  final int pageNumber;
  final int pageIndex;
  final String? chapterName;
  final PageChangeType changeType;
  /// Element count diff: e.g. {strokes: +3, images: -1}
  final int localStrokeCount;
  final int remoteStrokeCount;
  final int localImageCount;
  final int remoteImageCount;
  final int localShapeCount;
  final int remoteShapeCount;
  final int localTextCount;
  final int remoteTextCount;

  const PageChangeDetail({
    required this.fileName,
    required this.pageNumber,
    required this.pageIndex,
    this.chapterName,
    required this.changeType,
    this.localStrokeCount = 0,
    this.remoteStrokeCount = 0,
    this.localImageCount = 0,
    this.remoteImageCount = 0,
    this.localShapeCount = 0,
    this.remoteShapeCount = 0,
    this.localTextCount = 0,
    this.remoteTextCount = 0,
  });

  bool get hasElementDiff =>
      localStrokeCount != remoteStrokeCount ||
      localImageCount != remoteImageCount ||
      localShapeCount != remoteShapeCount ||
      localTextCount != remoteTextCount;
}

class PendingRemoteChanges {
  final NotebookMetadata metadata;
  final DocumentStructure document;
  final Map<String, PageData> pages;
  final Map<String, Uint8List> assets;

  /// Per-page change details for the UI.
  final List<PageChangeDetail> changedPages;
  final int newPageCount;
  final int modifiedPageCount;
  final int deletedPageCount;
  final int newAssetCount;

  /// fileNames where BOTH sides edited the page but the edits were disjoint
  /// (different elements), so they can be element-merged automatically at
  /// apply time instead of prompting the user. The pull decided this against
  /// the pull-start snapshot; [acceptRemoteChanges] re-merges with the LIVE
  /// local page (to fold in any mid-pull edits) and falls back to keeping
  /// local if the live re-merge turns out to conflict.
  final Set<String> autoMergeable;

  /// The server's authoritative page-file listing at pull time (every page the
  /// server currently has). [acceptRemoteChanges] uses it to tell a doc entry
  /// that is "pending hydration" (still on the server → keep) apart from a
  /// "ghost" (gone from the server, no local data → prune after N strikes).
  final Set<String> remotePageFileNames;

  /// fileNames the pull confirmed were deleted remotely (so their document
  /// entry is dropped immediately, not treated as a ghost).
  final Set<String> remoteDeletedFileNames;

  const PendingRemoteChanges({
    required this.metadata,
    required this.document,
    required this.pages,
    required this.assets,
    this.changedPages = const [],
    this.newPageCount = 0,
    this.modifiedPageCount = 0,
    this.deletedPageCount = 0,
    this.newAssetCount = 0,
    this.autoMergeable = const {},
    this.remotePageFileNames = const {},
    this.remoteDeletedFileNames = const {},
  });

  int get totalChanges => newPageCount + modifiedPageCount + deletedPageCount + newAssetCount;
}

// ═══════════════════════════════════════════════════════════════
//  PAGE CONFLICT — local vs remote for visual diff
// ═══════════════════════════════════════════════════════════════

class PageConflict {
  final String fileName;
  final int pageNumber;
  final String? chapterName;
  final PageData localPage;
  final PageData remotePage;
  /// Pre-decoded images for rendering local version in preview.
  final Map<String, ui.Image> localImageCache;
  /// Pre-decoded images for rendering remote version in preview.
  final Map<String, ui.Image> remoteImageCache;

  /// True when the conflict is "edited locally vs deleted remotely": the
  /// other device removed this page while we changed it. [remotePage] then
  /// has no real remote content (it mirrors [localPage] only so previews
  /// don't crash). Resolution must branch on this: accepting "remote" means
  /// honouring the deletion, not copying [remotePage] back over local.
  final bool isDeletion;

  const PageConflict({
    required this.fileName,
    required this.pageNumber,
    this.chapterName,
    required this.localPage,
    required this.remotePage,
    this.localImageCache = const {},
    this.remoteImageCache = const {},
    this.isDeletion = false,
  });
}

// ═══════════════════════════════════════════════════════════════
//  CANVAS STATE
// ═══════════════════════════════════════════════════════════════

/// Per-DocumentStructure cache for [CanvasState.filteredPageIndices].
/// Keyed on document identity so the entry is naturally GC'd when a
/// rebuild produces a different document. Holds the most recent
/// (activeChapterId, indices) tuple — single-slot is fine because
/// realistic UI only filters by one chapter at a time.
final Expando<({String? chapterId, List<int> indices})> _filteredIndicesCache =
    Expando();

class CanvasState {
  final NotebookMetadata metadata;
  final DocumentStructure document;
  final Map<String, PageData> pages;
  final int currentPageIndex;
  /// Last page index visited before navigating to [currentPageIndex].
  /// Used by the page navigation bar to show a "← previous" chip so the
  /// user can toggle between two pages without having to remember the
  /// number. `null` means no prior page (fresh notebook open).
  final int? previousPageIndex;
  final CanvasTool currentTool;
  final ToolSettings toolSettings;
  final List<StrokePoint> activeStroke;
  final double zoom;
  final Offset panOffset;
  final List<UndoEntry> undoStack;
  final List<UndoEntry> redoStack;
  final bool isDirty;
  final String remotePath;
  final LassoSelection? lassoSelection;
  final List<Offset> lassoPath;
  final Offset? eraserCursorPos;
  final Offset? shapeStartPos;
  final Offset? shapeEndPos;
  final bool showToolOptions;
  final String? selectedElementId;
  final Map<String, ui.Image> imageCache;
  final Map<String, Uint8List> assetBytes;
  final CanvasClipboard? clipboard;
  final List<SymbolLibrary> symbolLibraries;
  // Legacy flat symbols list — computed for backward compatibility.
  // Memoised by symbolLibraries identity via Expando (same trick as
  // _filteredIndicesCache below). Without this, every read in build
  // closures (popup-menu condition, context menu) re-walked all
  // libraries × symbols and allocated a fresh list.
  static final Expando<List<ReusableSymbol>> _symbolsCache = Expando();
  List<ReusableSymbol> get symbols {
    final cached = _symbolsCache[symbolLibraries];
    if (cached != null) return cached;
    final list = symbolLibraries.expand((l) => l.symbols).toList(growable: false);
    _symbolsCache[symbolLibraries] = list;
    return list;
  }
  // Interactive shape recognition: holds recognized shape while user adjusts
  final ShapeData? recognizedShape;
  final bool isAdjustingRecognized;
  final ReusableSymbol? pendingSymbol;
  final bool pendingPaste;
  final String? activeChapterId;
  final PendingRemoteChanges? pendingRemoteChanges;
  final List<PageConflict> pendingConflicts;

  /// Indices of pages visible under the active chapter filter (or all if null).
  ///
  /// Memoised on `document` identity + `activeChapterId`. With a 215-page
  /// notebook this getter used to allocate a fresh `List<int>` of length
  /// 215 (and walk all pages for the chapter filter) every time it was
  /// read — and the build path reads it 3-5× per rebuild and creates a
  /// derived `[i+1]` list of the same length, multiplying the work. The
  /// cache lets `Consumer.select((s) => s.filteredPageIndices)` actually
  /// compare-equal across rebuilds (identical list reference) so the
  /// chrome can skip rebuilding when the slice is genuinely unchanged.
  List<int> get filteredPageIndices {
    final cached = _filteredIndicesCache[document];
    if (cached != null && cached.chapterId == activeChapterId) {
      return cached.indices;
    }
    final result = activeChapterId == null
        ? List<int>.generate(document.pages.length, (i) => i, growable: false)
        : List<int>.unmodifiable([
            for (int i = 0; i < document.pages.length; i++)
              if (document.pages[i].chapterId == activeChapterId) i,
          ]);
    _filteredIndicesCache[document] =
        (chapterId: activeChapterId, indices: result);
    return result;
  }

  int get filteredPageCount => filteredPageIndices.length;

  /// Position of currentPageIndex within the filtered list (-1 if not found).
  int get currentFilteredIndex => filteredPageIndices.indexOf(currentPageIndex);

  const CanvasState({
    required this.metadata,
    required this.document,
    required this.pages,
    this.currentPageIndex = 0,
    this.previousPageIndex,
    this.currentTool = CanvasTool.pen,
    this.toolSettings = const ToolSettings(),
    this.activeStroke = const [],
    this.zoom = 2.0,
    this.panOffset = Offset.zero,
    this.undoStack = const [],
    this.redoStack = const [],
    this.isDirty = false,
    required this.remotePath,
    this.lassoSelection,
    this.lassoPath = const [],
    this.eraserCursorPos,
    this.shapeStartPos,
    this.shapeEndPos,
    this.showToolOptions = false,
    this.selectedElementId,
    this.imageCache = const {},
    this.assetBytes = const {},
    this.clipboard,
    this.symbolLibraries = const [],
    this.recognizedShape,
    this.isAdjustingRecognized = false,
    this.pendingSymbol,
    this.pendingPaste = false,
    this.activeChapterId,
    this.pendingRemoteChanges,
    this.pendingConflicts = const [],
  });

  PageData? get currentPage {
    if (document.pages.isEmpty) return null;
    // Guard against out-of-bounds index (shouldn't happen, but be safe).
    final safeIdx = currentPageIndex.clamp(0, document.pages.length - 1);
    final entry = document.pages[safeIdx];
    return pages[entry.fileName];
    //
    // Nota: in passato qui c'era un fallback che tornava la prima pagina
    // disponibile quando `pages[entry.fileName]` era null. Rimosso perché
    // mostrava il contenuto di un altro capitolo come se fosse la pagina
    // richiesta, mascherando pagine la cui data era andata persa sul
    // server ("nel capitolo 1P inv, dopo la pagina 41 in poi escono tutte
    // uguali alla prima pagina del capitolo Control").
    // Meglio mostrare "Nessuna pagina" così l'utente capisce che c'è un
    // problema reale e può usare il meccanismo di recovery (healMissing
    // Pages) invece di vedere dati sbagliati.
  }

  String get currentPageFileName {
    // Same out-of-bounds guard as [currentPage]: a remote merge/conflict
    // resolution can shrink `document.pages` while the index still points
    // past the end.
    final safeIdx = currentPageIndex.clamp(0, document.pages.length - 1);
    return document.pages[safeIdx].fileName;
  }
  int get pageCount => document.pages.length;

  /// True for a free-sketch notebook: one big "infinite" canvas instead of
  /// A4 pages. Drives the editor to hide page/chapter chrome, skip the page
  /// border/shadow, and use a fixed 1:1 render scale with free pan/zoom.
  bool get isScratch => metadata.paperType == AppConfig.infinitePaperType;

  PaperType get currentPaperType {
    final page = currentPage;
    if (page == null) return PaperType.blank;
    return paperTypeFromString(page.layers.background.type);
  }

  CanvasState copyWith({
    NotebookMetadata? metadata,
    DocumentStructure? document,
    Map<String, PageData>? pages,
    int? currentPageIndex,
    int? previousPageIndex,
    bool clearPreviousPage = false,
    CanvasTool? currentTool,
    ToolSettings? toolSettings,
    List<StrokePoint>? activeStroke,
    double? zoom,
    Offset? panOffset,
    List<UndoEntry>? undoStack,
    List<UndoEntry>? redoStack,
    bool? isDirty,
    String? remotePath,
    LassoSelection? lassoSelection,
    bool clearLasso = false,
    List<Offset>? lassoPath,
    Offset? eraserCursorPos,
    bool clearEraserCursor = false,
    Offset? shapeStartPos,
    bool clearShapeStart = false,
    Offset? shapeEndPos,
    bool clearShapeEnd = false,
    bool? showToolOptions,
    String? selectedElementId,
    bool clearSelectedElement = false,
    Map<String, ui.Image>? imageCache,
    Map<String, Uint8List>? assetBytes,
    CanvasClipboard? clipboard,
    bool clearClipboard = false,
    List<SymbolLibrary>? symbolLibraries,
    ShapeData? recognizedShape,
    bool clearRecognizedShape = false,
    bool? isAdjustingRecognized,
    ReusableSymbol? pendingSymbol,
    bool clearPendingSymbol = false,
    bool? pendingPaste,
    String? activeChapterId,
    bool clearActiveChapter = false,
    PendingRemoteChanges? pendingRemoteChanges,
    bool clearPendingRemoteChanges = false,
    List<PageConflict>? pendingConflicts,
    bool clearPendingConflicts = false,
  }) =>
      CanvasState(
        metadata: metadata ?? this.metadata,
        document: document ?? this.document,
        pages: pages ?? this.pages,
        currentPageIndex: currentPageIndex ?? this.currentPageIndex,
        previousPageIndex: clearPreviousPage
            ? null
            : (previousPageIndex ?? this.previousPageIndex),
        currentTool: currentTool ?? this.currentTool,
        toolSettings: toolSettings ?? this.toolSettings,
        activeStroke: activeStroke ?? this.activeStroke,
        zoom: zoom ?? this.zoom,
        panOffset: panOffset ?? this.panOffset,
        undoStack: undoStack ?? this.undoStack,
        redoStack: redoStack ?? this.redoStack,
        isDirty: isDirty ?? this.isDirty,
        remotePath: remotePath ?? this.remotePath,
        lassoSelection: clearLasso ? null : (lassoSelection ?? this.lassoSelection),
        lassoPath: lassoPath ?? this.lassoPath,
        eraserCursorPos: clearEraserCursor ? null : (eraserCursorPos ?? this.eraserCursorPos),
        shapeStartPos: clearShapeStart ? null : (shapeStartPos ?? this.shapeStartPos),
        shapeEndPos: clearShapeEnd ? null : (shapeEndPos ?? this.shapeEndPos),
        showToolOptions: showToolOptions ?? this.showToolOptions,
        selectedElementId: clearSelectedElement ? null : (selectedElementId ?? this.selectedElementId),
        imageCache: imageCache ?? this.imageCache,
        assetBytes: assetBytes ?? this.assetBytes,
        clipboard: clearClipboard ? null : (clipboard ?? this.clipboard),
        symbolLibraries: symbolLibraries ?? this.symbolLibraries,
        recognizedShape: clearRecognizedShape ? null : (recognizedShape ?? this.recognizedShape),
        isAdjustingRecognized: isAdjustingRecognized ?? this.isAdjustingRecognized,
        pendingSymbol: clearPendingSymbol ? null : (pendingSymbol ?? this.pendingSymbol),
        pendingPaste: pendingPaste ?? this.pendingPaste,
        activeChapterId: clearActiveChapter ? null : (activeChapterId ?? this.activeChapterId),
        pendingRemoteChanges: clearPendingRemoteChanges ? null : (pendingRemoteChanges ?? this.pendingRemoteChanges),
        pendingConflicts: clearPendingConflicts ? const [] : (pendingConflicts ?? this.pendingConflicts),
      );
}

class UndoEntry {
  final String pageFileName;
  final PageData pageData;
  UndoEntry(this.pageFileName, this.pageData);
}
