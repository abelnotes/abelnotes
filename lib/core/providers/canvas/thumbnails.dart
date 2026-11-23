import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';

/// Library cover thumbnail refresh, kept off the pen's path.
class Thumbnails {
  Thumbnails(this._core, this._waitForQuietPointer, {bool? debounced})
      : _debounced = debounced ?? kIsWeb;

  final CanvasCore _core;
  final bool _debounced;
  final Future<void> Function() _waitForQuietPointer;
  Timer? _timer;
  Future<void> Function()? _job;

  /// Refreshes the library thumbnail from the first page, off the pen's
  /// path; failures are swallowed (tiles fall back to their placeholder).
  void refresh(CanvasState s, String notebookId) {
    _queue(() async {
      try {
        // Rendering records a full page paint on the UI isolate: never
        // while the pen is down.
        await _waitForQuietPointer();
        final thumbs = _core.ref.read(thumbnailServiceProvider);
        final first = s.document.pages.isNotEmpty ? s.document.pages.first : null;
        final page = first == null ? null : s.pages[first.fileName];
        if (page == null) return;
        // Raw asset bytes too: images the canvas has not decoded yet would
        // otherwise render as blank rectangles.
        await thumbs.renderAndCache(notebookId, page,
            imageCache: s.imageCache, assetBytes: s.assetBytes);
      } catch (e) {
        debugPrint('[Canvas] Thumbnail cache failed: $e');
      }
    });
  }

  /// Cover thumbnail refresh. On web a PNG encode right after every save
  /// is a visible hitch, so wait until saves stop; closing flushes it.
  void _queue(Future<void> Function() job) {
    _job = job;
    if (!_debounced) return flush();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), flush);
  }

  /// Runs the queued refresh now, if any.
  void flush() {
    _timer?.cancel();
    _timer = null;
    final job = _job;
    _job = null;
    if (job != null) unawaited(job());
  }

  /// Drops the debounce and the queued refresh, so nothing outlives the notifier.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _job = null;
  }
}
