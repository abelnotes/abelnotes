import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Raster stand-in for the static page layers while the zoom is changing.
///
/// CanvasKit replays the vector picture (strokes tessellated in WASM) on
/// every frame of a zoom gesture; drawing one cached bitmap with the live
/// transform is far cheaper. Once the zoom stops for [settle] the owner is
/// notified and the crisp vector picture takes over again.
class ZoomSnapshot extends ChangeNotifier {
  static const settle = Duration(milliseconds: 140);

  ui.Image? _image;
  Object? _page;
  String? _lassoKey;
  int? _imageSig;
  ui.Rect _region = ui.Rect.zero;

  Object? _lastPage;
  double? _lastZoom;
  bool _zooming = false;
  Timer? _timer;
  bool _broken = false;

  // Bitmap tiles of the static layers at one scale, anchored to the page so
  // panning keeps them; see CanvasRenderEngine._paintLiveBitmap.
  final Map<int, ui.Image> liveTiles = {};
  Object? livePage;
  Object? liveKey;

  bool bakeDue = false;
  Timer? _bakeTimer;

  Object? _warmKey;

  /// Same view for 350 ms: time to build the bitmap while nothing moves.
  void warm(Object key) {
    if (_warmKey != key) {
      _warmKey = key;
      _bakeTimer?.cancel();
      bakeDue = false;
    }
    scheduleBake(350);
  }

  bool warmReady(Object key) => bakeDue && _warmKey == key;

  /// Ask for a repaint once the pen has rested, to merge new strokes into the bitmap.
  void scheduleBake([int ms = 900]) {
    if (bakeDue || (_bakeTimer?.isActive ?? false)) return;
    _bakeTimer = Timer(Duration(milliseconds: ms), () {
      bakeDue = true;
      notifyListeners();
    });
  }

  void cancelBake() {
    _bakeTimer?.cancel();
    bakeDue = false;
  }

  void clearLive() {
    cancelBake();
    for (final t in liveTiles.values) {
      t.dispose();
    }
    liveTiles.clear();
    livePage = null;
    liveKey = null;
  }

  /// Snapshot creation threw once (no toImageSync on this backend): stay on vector.
  void markBroken() {
    _broken = true;
    _zooming = false;
  }

  /// Call once per paint. True while the zoom is moving (until [settle]
  /// after the last change); a different page resets the tracking.
  bool track(double zoom, Object page) {
    if (_broken) return false;
    if (!identical(page, _lastPage)) {
      _lastPage = page;
      _zooming = false;
      _timer?.cancel();
    } else if (_lastZoom != null && zoom != _lastZoom) {
      _zooming = true;
      _timer?.cancel();
      _timer = Timer(settle, () {
        _zooming = false;
        notifyListeners();
      });
    }
    _lastZoom = zoom;
    return _zooming;
  }

  /// Snapshot if it was taken from this exact page state, else null.
  ui.Image? lookup(Object page, String lassoKey, int imageSig) {
    if (_image != null &&
        identical(_page, page) &&
        _lassoKey == lassoKey &&
        _imageSig == imageSig) {
      return _image;
    }
    return null;
  }

  ui.Rect get region => _region;

  void store(ui.Image image, Object page, String lassoKey, int imageSig,
      ui.Rect region) {
    _image?.dispose();
    _image = image;
    _page = page;
    _lassoKey = lassoKey;
    _imageSig = imageSig;
    _region = region;
  }

  void clear() {
    clearLive();
    _image?.dispose();
    _image = null;
    _page = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bakeTimer?.cancel();
    clear();
    super.dispose();
  }
}
