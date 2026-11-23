import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// What the notifier's collaborators may use of it.
abstract interface class CanvasCore {
  Ref get ref;
  CanvasState? get state;
  set state(CanvasState? value);

  /// True once the notifier is disposed: async work must stop touching it.
  bool get isDisposed;

  /// [page] with [content] swapped in, its PDF text layer carried over.
  PageData pageWithContent(PageData page, List<ContentElement> content,
      {List<String>? assetReferences});

  /// Next free z-index on [page].
  int nextZIndex(PageData page);

  /// Asset ids bucketed by byte length, for the dedup check.
  Map<int, List<String>> get assetsByLength;

  /// Queues [assetKey] for upload and for the next local write.
  void markAssetDirty(String assetKey);

  /// [page] with [element] appended.
  PageData pageWithNewElement(PageData page, ContentElement element);

  /// The undo stack of [s] with [page] pushed (capped).
  List<UndoEntry> pushUndo(CanvasState s, String fileName, PageData page);

  /// Id of an existing asset with bytes identical to [bytes], or null.
  String? findIdenticalAsset(Uint8List bytes, Map<String, Uint8List> assets);

  /// True while a bulk operation (PDF import) runs: no eager image decode.
  bool get bulkOperationInProgress;

  /// Writes an edited page back (dirty, redo dropped, [undoOf] as one undo step).
  void commitPageEdit(CanvasState s, String fileName, PageData after,
      {PageData? undoOf,
      bool history = true,
      CanvasState Function(CanvasState)? alsoState});

  /// Pan that centres [page] (default: the current one) at [zoom].
  Offset centeredPanOffset(double zoom, [PageData? page]);
}
