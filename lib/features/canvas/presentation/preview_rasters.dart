import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Web: page previews as bitmaps, each made once.
///
/// CanvasKit replays a vector picture by re-stroking every path, so a grid
/// of page previews redrew all their ink on every frame of a scroll or of the
/// sheet sliding in. A bitmap is one blit. Bitmaps are made a few at a time
/// between frames, so opening the grid never waits for all of them.
class PreviewRasters {
  PreviewRasters._();
  static final PreviewRasters instance = PreviewRasters._();

  /// Bumped when bitmaps were made; previews rebuild to pick them up.
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  // Insertion order = recency (lookups move a key to the end).
  final LinkedHashMap<PreviewKey, ui.Image> _images = LinkedHashMap();
  final LinkedHashMap<PreviewKey, ui.Image Function()> _queue = LinkedHashMap();
  final Set<PreviewKey> _failed = {};
  bool _running = false;

  // About two screens of previews. Dropped bitmaps are not disposed: a
  // preview still on screen may hold one; CanvasKit frees it once unused.
  static const int _max = 48;

  ui.Image? lookup(PreviewKey key) {
    final img = _images.remove(key);
    if (img != null) _images[key] = img;
    return img;
  }

  /// True when [key] could not be made: draw it as a vector instead.
  bool failed(PreviewKey key) => _failed.contains(key);

  void request(PreviewKey key, ui.Image Function() render) {
    if (_images.containsKey(key) || _failed.contains(key)) return;
    _queue[key] = render;
    if (!_running) {
      _running = true;
      Timer.run(_work);
    }
  }

  void _work() {
    final sw = Stopwatch()..start();
    var made = false;
    while (_queue.isNotEmpty) {
      final key = _queue.keys.first;
      final render = _queue.remove(key)!;
      try {
        _images[key] = render();
        made = true;
      } catch (_) {
        _failed.add(key);
      }
      while (_images.length > _max) {
        _images.remove(_images.keys.first);
      }
      // Leave the rest to the next turn so a frame can be drawn in between.
      if (sw.elapsedMilliseconds >= 8) break;
    }
    if (made || _queue.isEmpty) version.value++;
    if (_queue.isEmpty) {
      _running = false;
    } else {
      Timer.run(_work);
    }
  }
}

/// A preview bitmap of one page state at one size. Pages and image caches are
/// compared by identity: both are replaced, never changed in place.
@immutable
class PreviewKey {
  const PreviewKey(this.page, this.width, this.height, this.images);
  final Object page;
  final int width;
  final int height;
  final Object images;

  @override
  bool operator ==(Object other) =>
      other is PreviewKey &&
      identical(other.page, page) &&
      identical(other.images, images) &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(
      identityHashCode(page), identityHashCode(images), width, height);
}
