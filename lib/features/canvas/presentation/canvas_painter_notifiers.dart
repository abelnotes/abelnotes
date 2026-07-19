// ═══════════════════════════════════════════════════════════════
//  canvas_painter_notifiers.dart
//
//  Lightweight ChangeNotifiers used for zero-Riverpod-rebuild
//  rendering of active strokes and lasso paths during drawing.
//  Extracted from canvas_screen.dart.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io' as io;
import 'dart:math' show sqrt;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// High-performance stroke tracker — bypasses Riverpod so every new point
/// does NOT trigger a full widget tree rebuild.
///
/// The CanvasScreen subscribes to this directly via [ListenableBuilder],
/// which only repaints the canvas layer, not the toolbar or page nav.
class ActiveStrokeNotifier extends ChangeNotifier {
  final List<StrokePoint> _points = [];
  bool _active = false;

  /// True when running on a desktop OS (Windows / macOS / Linux).
  ///
  /// Desktop graphics tablets produce ADC jitter that requires a wider
  /// smoothing window than Apple Pencil on iPad, which delivers hardware-
  /// filtered, 120 Hz coalesced events.
  bool _isDesktop = false;

  /// True when the pointing device reports no pressure (mouse / touchpad /
  /// some plain touch panels). When set, [addPoint] synthesises a velocity-
  /// derived pseudo-pressure so the rendered stroke isn't stuck at a flat
  /// 0.5 fallback. Detected from the first [start] pressure: anything <= 0
  /// means "no real pressure data", at which point we synth.
  bool _synthPressure = false;
  /// EMA state for synth pressure (0..1). Smoothed across points so width
  /// modulation isn't choppy on irregular sample rates.
  double _synthEma = 0.6;

  /// Page units per LOGICAL screen pixel for the current stroke
  /// (1 / (zoom × renderScale)), set by [start]. 0 = unknown. Used by the
  /// Windows quantization filter below to translate page-space deltas back
  /// into screen pixels.
  double _pageUnitsPerPx = 0;

  /// Raw (unsmoothed) cursor position of the most recent [addPoint] call.
  /// With the lazy-brush model the emitted tip trails the cursor by the
  /// string radius; [snapshotForCommit] appends this position so the
  /// committed stroke ends where the user actually released.
  Offset? _lastRawPos;

  /// True while the current stroke is driven by the lazy-brush (pulled
  /// string) model — mouse/touchpad on desktop with a known screen scale.
  bool _lazyBrush = false;

  List<StrokePoint> get points => _points;
  bool get isActive => _active;

  void start(Offset pos, double pressure, {double pageUnitsPerPx = 0}) {
    _points.clear();
    _active = true;
    _pageUnitsPerPx = pageUnitsPerPx;
    _lastRawPos = pos;
    _lazyBrush = false;
    _isDesktop = !kIsWeb &&
        (io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux);
    // Devices without pressure (mouse, touchpad, plain touch) report 0.
    // Stylus / Apple Pencil always report > 0, so this check leaves the
    // pen-input pipeline bit-equivalent.
    _synthPressure = pressure <= 0.0;
    _synthEma = 0.6;
    final p0 = _synthPressure ? 0.6 : pressure;
    _points.add(StrokePoint(x: pos.dx, y: pos.dy, pressure: p0,
        timestamp: DateTime.now().millisecondsSinceEpoch));
    notifyListeners();
  }

  void addPoint(Offset pos, double pressure) {
    // Always remember where the cursor really is — snapshotForCommit
    // completes the lazy-brush tail from here even when this sample gets
    // rejected or absorbed by the dead zone below.
    _lastRawPos = pos;
    // ── Jitter rejection ────────────────────────────────────────────────────
    // Drop points that are < 0.4 page-units from the previous point.
    // On desktop tablets this eliminates ADC noise without losing real movement.
    if (_points.isNotEmpty) {
      final last = _points.last;
      final dx = pos.dx - last.x;
      final dy = pos.dy - last.y;
      if (dx * dx + dy * dy < 0.16) return; // 0.4² = 0.16
    }

    // De-latch synth mode: pressure can arrive a few ms AFTER pointer-down
    // on Linux (the evdev pressure stream is independent of the pointer
    // stream), so a stroke can start in velocity-synth even though the pen
    // is reporting real pressure. As soon as a real (>0) sample shows up,
    // switch to the real-pressure path for the rest of the stroke so width
    // follows the pen. One-way only — we never re-latch to synth mid-stroke
    // (a momentary 0 from a dropped read shouldn't flip a real pen to synth).
    if (_synthPressure && pressure > 0.0) {
      _synthPressure = false;
    }

    double sx = pos.dx, sy = pos.dy, sp = pressure;

    // Smoothing branch routing — by INPUT KIND, not sample rate. The
    // previous time-based detection (≤8ms inter-sample) failed on PC
    // graphics tablets because Flutter coalesces pointer events to
    // frame rate (~16ms = 60Hz) regardless of the tablet's true 200-
    // 300 Hz rate. So Wacom users still got the heavy desktop branch
    // and the visible pen-tip lag. _synthPressure==false means the
    // device delivered real pressure (i.e. it's a stylus — Apple
    // Pencil OR a graphics tablet) and is already hardware-smoothed;
    // the heavy 5-point window adds drag without removing real noise.
    // _synthPressure==true means mouse/touchpad — chunky 60Hz deltas
    // that genuinely need heavier smoothing.
    final useDesktopHeavy = _isDesktop && _synthPressure;

    if (useDesktopHeavy) {
      // ── Desktop / mouse / tablet-as-mouse smoothing (velocity-adaptive) ──
      //
      // A fixed history-weighted window (the old 5-point average, current ≈
      // 38 %) irons out digitiser jitter but also pulls every sample INWARD
      // toward the recent path. On a fast, WIDE gesture that lag clips the
      // peaks — the user's big sweep comes out shrunken/"attenuated" (the
      // reported bug). Many Linux graphics tablets mapped via xinput report
      // NO pressure, so they land in this branch too and suffered the same
      // shrinkage.
      //
      // Fix: a single-pole filter whose weight on the CURRENT point scales
      // with how far that point jumped from the last one (a proxy for pen
      // speed). The CRITICAL part is the UPPER bound. The previous version
      // capped alpha at 0.9, so EVERY sample lost 10 % of its inter-sample
      // delta — and with Flutter's ~60 Hz coalescing a fast, wide sweep is
      // only a handful of sparse samples, so that 10 % compounded into a
      // visibly shrunken gesture ("me li attenua i movimenti larghi").
      //
      // New mapping: only genuine ADC jitter (sub-~1 page-unit wiggle, which
      // the 0.4-unit reject above already trims) is smoothed (alpha 0.5);
      // any deliberate movement ramps to alpha == 1.0 (TRUE passthrough, no
      // extent loss) by ~3 page-units of travel. Wide/fast strokes therefore
      // keep their full reach; only near-still hand tremor is ironed out.
      if (_pageUnitsPerPx > 0 && _points.isNotEmpty) {
        // ── Lazy brush (pulled string) — Krita/Photoshop-style ──
        // The emitted tip is dragged behind the cursor by a virtual
        // string of ~3 screen px. Mouse coordinates are integer pixels
        // (no sub-pixel source exists for WM_MOUSEMOVE), and the ±0.5 px
        // quantization staircase — which zoomed out spans 1-2 page units
        // and used to render as a LIVE wavy line — never exceeds the
        // string length, so the tip simply does not react to it. An EMA
        // only damps that noise; the dead zone removes it. Cost: the
        // stroke trails the cursor by the radius (the committed tail is
        // completed from `_lastRawPos` in [snapshotForCommit]) and
        // corners round by ≤ ~3 px — the same trade Photoshop's
        // "smoothing" makes. The radius lives in SCREEN px, so fine
        // detail at high zoom is untouched.
        _lazyBrush = true;
        final last = _points.last;
        final ddx = pos.dx - last.x;
        final ddy = pos.dy - last.y;
        final dist = sqrt(ddx * ddx + ddy * ddy);
        final r = 3.0 * _pageUnitsPerPx;
        if (dist <= r) return; // inside the dead zone: the brush stays put
        final k = (dist - r) / dist;
        sx = last.x + ddx * k;
        sy = last.y + ddy * k;
        sp = last.pressure + (pressure - last.pressure) * k;
      } else if (_points.isNotEmpty) {
        // Screen scale unknown — fall back to the velocity-adaptive EMA.
        final last = _points.last;
        final ddx = pos.dx - last.x;
        final ddy = pos.dy - last.y;
        final dist = sqrt(ddx * ddx + ddy * ddy);
        final alpha =
            dist <= 1.0 ? 0.5 : (0.5 + (dist - 1.0) / 4.0).clamp(0.5, 1.0);
        sx = last.x + ddx * alpha;
        sy = last.y + ddy * alpha;
        sp = last.pressure + (pressure - last.pressure) * alpha;
      }
    } else if (_isDesktop && !_synthPressure) {
      // ── PC graphics tablet (Wacom/Huion/Gaomon) — geometry PASSTHROUGH ─
      // The driver already heavily filters the digitiser stream.
      // Flutter then coalesces to ~60 Hz frame rate, so each sample
      // we receive is sparse along a fast curve. Even the iPad-
      // equivalent 20% history-blend below biased every sample
      // INWARD relative to the user's real hand motion — on a fast
      // C the result was visibly wavy/oscillating ("ondulata"). For
      // PC stylus we trust the hardware and don't smooth POSITION at
      // all; any de-jitter must come from the renderer's Catmull-Rom
      // interpolation.
      //
      // PRESSURE is a different story. On Linux it comes from the
      // native GDK bridge (LinuxPenPressure.latest()), which pairs
      // "the most recent native sample" with whichever pointer event
      // dispatches next — so consecutive points can carry a duplicated
      // pressure then a jump (staircase). Rendered, that staircase is
      // the "thick/thin sections with no clean blend" on a letter C.
      // A 50/50 EMA on pressure ONLY (geometry untouched, so no curve
      // distortion) restores a continuous width signal; the renderer's
      // own width-smoothing passes then have a clean input to work on.
      if (_points.isNotEmpty) {
        sp = _points.last.pressure * 0.5 + pressure * 0.5;
      }
      // ── Windows: integer-pixel quantization dejitter ──
      // The Windows embedder reads WM_POINTER positions from
      // ptPixelLocation — INTEGER client pixels — so the sub-pixel
      // precision of the digitizer never reaches Dart (Linux/GDK and
      // iPad deliver float coords; that's why the passthrough above is
      // fine there). The ±0.5 px staircase is invisible at high zoom,
      // but zoomed out 1 px ≈ 1.5-2+ PAGE units — comparable to the
      // stroke width — and the renderer's Catmull-Rom faithfully turns
      // it into a smooth WAVE ("ondulato", worst on slow vertical
      // strokes). EMA whose weight on the new point ramps from 0.3
      // (steps ≲ quantization scale = mostly noise) to 1.0 (≥ 4 px =
      // deliberate movement, true passthrough so wide gestures keep
      // their full reach).
      if (!kIsWeb &&
          io.Platform.isWindows &&
          _pageUnitsPerPx > 0 &&
          _points.isNotEmpty) {
        final last = _points.last;
        final ddx = pos.dx - last.x;
        final ddy = pos.dy - last.y;
        final stepPx = sqrt(ddx * ddx + ddy * ddy) / _pageUnitsPerPx;
        final alpha =
            stepPx >= 4.0 ? 1.0 : (0.3 + 0.7 * (stepPx / 4.0)).clamp(0.3, 1.0);
        sx = last.x + ddx * alpha;
        sy = last.y + ddy * alpha;
      }
    } else {
      // ── Touch / Apple Pencil smoothing (very light, high current-weight) ─
      // Apple Pencil is already hardware-filtered at 120 Hz. A 3-point
      // window with ~80 % weight on the current point removes sub-pixel
      // ADC jitter without perceptible drag. Kept for iPad path; PC
      // stylus skips it (above branch) because Flutter's 60 Hz
      // coalescing makes every history blend visibly distort fast curves.
      if (_points.length >= 2) {
        final p1 = _points[_points.length - 1];
        final p0 = _points[_points.length - 2];
        sx = (p0.x + p1.x * 3 + pos.dx * 16) / 20;
        sy = (p0.y + p1.y * 3 + pos.dy * 16) / 20;
        sp = (p0.pressure + p1.pressure * 3 + pressure * 16) / 20;
      } else if (_points.length == 1) {
        final p1 = _points.last;
        sx = (p1.x + pos.dx * 7) / 8;
        sy = (p1.y + pos.dy * 7) / 8;
        sp = (p1.pressure + pressure * 7) / 8;
      }
    }

    // Synthesise a velocity-derived pseudo-pressure for devices without real
    // pressure (mouse / touchpad). Slow movement → high pressure (full body),
    // fast movement → low pressure (thin), smoothed by an EMA so width
    // modulation isn't jittery on irregular sample rates. Range [0.30, 0.85]
    // stays inside the renderer's existing pressureFactor mapping
    // (0.45 + p*0.60), giving a stroke that breathes 0.63→0.96 of baseWidth
    // before the velocity factor is applied — very close to a stylus feel.
    if (_synthPressure && _points.isNotEmpty) {
      final last = _points.last;
      final dx2 = pos.dx - last.x;
      final dy2 = pos.dy - last.y;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final dt = nowMs - last.timestamp;
      final dtMs = dt < 1 ? 1 : dt;
      // Page-units PER SECOND (was per-sample). Independent of the
      // input device's capture rate. ~1500 px/s = "fast scribble" —
      // matches the renderer's velocity scale (divisor 2500, clamp
      // 0.40) so synth pressure and real pressure thin similarly.
      final v = sqrt(dx2 * dx2 + dy2 * dy2) * 1000.0 / dtMs;
      final target = (0.85 - (v / 1500.0).clamp(0.0, 0.55)).clamp(0.30, 0.85);
      _synthEma = _synthEma * 0.7 + target * 0.3;
      sp = _synthEma;
    }

    // NO linear resampling between sparse pointer events: an earlier
    // attempt to densify by inserting linear-interpolated samples on
    // gap > 12 page-units made medium-speed strokes worse. Linear
    // interpolation flattens the user's curved hand motion into a
    // chord between two organic samples; Catmull-Rom over a mix of
    // organic and linear-injected control points then literally
    // followed the chord, producing visible "polyline" feel exactly
    // when the user wrote at moderate speed (where samples were
    // sparse enough to trigger the densifier but the gesture was
    // still continuously curved). Trust the renderer's adaptive
    // Catmull-Rom to handle sparse control points correctly.
    _points.add(StrokePoint(
      x: sx, y: sy, pressure: sp,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    notifyListeners();
  }

  /// Copy of the live points for committing, with Windows integer-pixel
  /// quantization noise refitted out.
  ///
  /// Windows delivers mouse (always) and pen (when the sub-pixel bridge
  /// has no data) positions on an integer pixel grid. The live EMA can
  /// only partially damp the resulting ±0.5 px staircase without adding
  /// lag, so the wave survives into the committed stroke ("rimane
  /// brutto"). At commit time lag doesn't exist — run a few passes of
  /// weighted position smoothing with the KEY safety property that every
  /// point's total displacement from where it was actually sampled is
  /// clamped to ≤ 0.75 screen px (the quantization noise amplitude). The
  /// wave — whose amplitude is exactly that noise — is flattened, while
  /// genuine geometry (sharp corners, wide sweeps) cannot be distorted
  /// beyond the invisible noise floor BY CONSTRUCTION. No-op off Windows,
  /// when the stroke used sub-pixel pen data (_pageUnitsPerPx == 0), or
  /// for tiny strokes.
  List<StrokePoint> snapshotForCommit() {
    final pts = List<StrokePoint>.from(_points);
    // Lazy-brush strokes trail the cursor by the string radius — finish
    // the line out to where the user actually released.
    final raw = _lastRawPos;
    if (_lazyBrush && raw != null && pts.isNotEmpty) {
      final last = pts.last;
      final ddx = raw.dx - last.x;
      final ddy = raw.dy - last.y;
      if (ddx * ddx + ddy * ddy > 0.16) {
        pts.add(StrokePoint(
          x: raw.dx,
          y: raw.dy,
          pressure: last.pressure,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }
    if (kIsWeb ||
        !io.Platform.isWindows ||
        _pageUnitsPerPx <= 0 ||
        pts.length < 5) {
      return pts;
    }
    final maxShift = 0.75 * _pageUnitsPerPx; // page units
    var cur = pts;
    for (int pass = 0; pass < 3; pass++) {
      final next = List<StrokePoint>.from(cur);
      for (int i = 2; i < cur.length - 2; i++) {
        final ax = (cur[i - 2].x +
                2 * cur[i - 1].x +
                3 * cur[i].x +
                2 * cur[i + 1].x +
                cur[i + 2].x) /
            9;
        final ay = (cur[i - 2].y +
                2 * cur[i - 1].y +
                3 * cur[i].y +
                2 * cur[i + 1].y +
                cur[i + 2].y) /
            9;
        // Clamp the CUMULATIVE displacement against the original sample,
        // not the previous pass — repeated passes can't creep past it.
        var dx = ax - pts[i].x;
        var dy = ay - pts[i].y;
        final d = sqrt(dx * dx + dy * dy);
        if (d > maxShift) {
          dx *= maxShift / d;
          dy *= maxShift / d;
        }
        next[i] = StrokePoint(
          x: pts[i].x + dx,
          y: pts[i].y + dy,
          pressure: cur[i].pressure,
          timestamp: cur[i].timestamp,
        );
      }
      cur = next;
    }
    return cur;
  }

  void clearPoints() {
    _points.clear();
    notifyListeners();
  }

  void clear() {
    _points.clear();
    _active = false;
    _lastRawPos = null;
    _lazyBrush = false;
    notifyListeners();
  }

  /// Resume tracking with the provided history. Used to recover from
  /// spurious PointerUp+PointerDown sequences on iPad where the pen
  /// never actually lifted — without this, each segment would commit
  /// as its own stroke and the user would see a mid-letter break.
  ///
  /// The synth-pressure / desktop flags are preserved (they were set
  /// by the original [start] call and survive [clear]); _synthEma is
  /// re-anchored to the last point's pressure so width modulation
  /// continues smoothly across the seam.
  void restoreActive(List<StrokePoint> previousPoints) {
    _points.clear();
    if (previousPoints.isNotEmpty) {
      _points.addAll(previousPoints);
      _synthEma = previousPoints.last.pressure.clamp(0.30, 0.85).toDouble();
    }
    _active = true;
    notifyListeners();
  }
}

/// Live transform of an existing lasso selection (drag offset / rotation /
/// scale) tracked locally so every pointer-move event doesn't fire a full
/// Riverpod state update. The painter reads the live values via [snapshot]
/// and the CustomPaint listens on [this] to schedule repaint without
/// rebuilding the widget tree above it.
class LassoTransformNotifier extends ChangeNotifier {
  bool _active = false;
  Offset _dragOffset = Offset.zero;
  double _rotation = 0.0;
  double _scale = 1.0;

  bool get isActive => _active;
  Offset get dragOffset => _dragOffset;
  double get rotation => _rotation;
  double get scale => _scale;

  ({Offset dragOffset, double rotation, double scale}) snapshot() =>
      (dragOffset: _dragOffset, rotation: _rotation, scale: _scale);

  void begin({
    Offset dragOffset = Offset.zero,
    double rotation = 0.0,
    double scale = 1.0,
  }) {
    _active = true;
    _dragOffset = dragOffset;
    _rotation = rotation;
    _scale = scale;
    notifyListeners();
  }

  void translate(Offset delta) {
    if (!_active) return;
    _dragOffset += delta;
    notifyListeners();
  }

  void rotateBy(double delta) {
    if (!_active) return;
    _rotation += delta;
    notifyListeners();
  }

  void setScale(double s) {
    if (!_active) return;
    _scale = s;
    notifyListeners();
  }

  void end() {
    if (!_active) return;
    _active = false;
    _dragOffset = Offset.zero;
    _rotation = 0.0;
    _scale = 1.0;
    notifyListeners();
  }
}

/// Live drag/rotate/resize of a single non-lasso selected element
/// (image / shape / text picked via double-tap). Same pattern as
/// LassoTransformNotifier: pan-update writes go here instead of into
/// Riverpod, the painter reads the live values each frame, and Riverpod
/// catches up exactly once on pan-end.
class ElementTransformNotifier extends ChangeNotifier {
  String? _elementId;
  // Live page-space delta applied to the element's stored (x, y).
  Offset _dragOffset = Offset.zero;
  // Live rotation delta added to the element's stored rotation.
  double _rotationDelta = 0.0;
  // Live multiplicative scale applied to the element's stored
  // (width, height) — only used by resize.
  double _scaleW = 1.0;
  double _scaleH = 1.0;
  // Element's bounds at gesture-start, in page coords. Captured once on
  // [begin] and held immutable until [end]. The resize handler divides
  // newBounds.width by toScreen(_origBounds).width to compute a TRUE
  // cumulative scale relative to the original element. Without this, the
  // handler used the live (already-scaled) bounds as the divisor and
  // produced per-tick relative scales — which the [setScale] (replace
  // semantics) overwrote each tick, making the image jiggle around 110%
  // regardless of how far the user dragged.
  Rect? _origBounds;

  bool get isActive => _elementId != null;
  String? get elementId => _elementId;
  Offset get dragOffset => _dragOffset;
  double get rotationDelta => _rotationDelta;
  double get scaleW => _scaleW;
  double get scaleH => _scaleH;
  Rect? get origBounds => _origBounds;

  void begin(String elementId, {Rect? origBounds}) {
    _elementId = elementId;
    _origBounds = origBounds;
    _dragOffset = Offset.zero;
    _rotationDelta = 0.0;
    _scaleW = 1.0;
    _scaleH = 1.0;
    notifyListeners();
  }

  void translate(Offset delta) {
    if (_elementId == null) return;
    _dragOffset += delta;
    notifyListeners();
  }

  void rotateBy(double delta) {
    if (_elementId == null) return;
    _rotationDelta += delta;
    notifyListeners();
  }

  /// Replace the live scale (e.g. when the user drags a corner handle —
  /// the screen helper has already converted the new bounds back to a
  /// (sw, sh) factor relative to the original bounds).
  void setScale(double sw, double sh) {
    if (_elementId == null) return;
    _scaleW = sw;
    _scaleH = sh;
    notifyListeners();
  }

  void end() {
    _elementId = null;
    _origBounds = null;
    _dragOffset = Offset.zero;
    _rotationDelta = 0.0;
    _scaleW = 1.0;
    _scaleH = 1.0;
    notifyListeners();
  }
}

/// Laser-pointer trail — points are tagged with timestamps and the
/// painter renders them with an opacity that fades to zero over
/// [trailMs]. Once a point has fully faded it's pruned from the
/// buffer. Never committed to a page (this is presentation ink, not
/// annotation ink).
class LaserStrokeNotifier extends ChangeNotifier {
  /// Total fade-out window in ms. ~1.5 s feels right — long enough to
  /// follow the user pointing out something on a page, short enough not
  /// to clutter when they sweep around.
  static const int trailMs = 1500;

  /// Each point carries a `start` flag set true on the FIRST point of a
  /// gesture (pointer-down). The painter uses it to split sub-paths so
  /// the trail doesn't bridge two distinct laser strokes with a long
  /// straight line — that was the "collega il punto vecchio con quello
  /// nuovo" bug.
  final List<({double x, double y, int t, bool start})> _points = [];
  Timer? _ticker;
  // Set in dispose(). Pointer events queued before disposal can still fire
  // addPoint() afterwards (the State is gone but the event is in flight);
  // without this guard that would recreate the ticker / call
  // notifyListeners() on a dead ChangeNotifier and throw.
  bool _disposed = false;

  List<({double x, double y, int t, bool start})> get points => _points;

  /// Append a point. [start] marks pointer-down — see field doc above.
  /// 16ms interval (60 Hz) aligns with typical display refresh; the
  /// previous 30 ms (33 Hz) beat against 60 Hz displays and produced
  /// the "scatti" the user reported.
  void addPoint(Offset pos, {bool start = false}) {
    if (_disposed) return;
    _points.add((
      x: pos.dx,
      y: pos.dy,
      t: DateTime.now().millisecondsSinceEpoch,
      start: start,
    ));
    _ticker ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      _prune();
    });
    notifyListeners();
  }

  void _prune() {
    if (_disposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - trailMs;
    // Find the FIRST point that's still within the fade window — points
    // earlier than that are stale and must go. Single removeRange beats
    // the previous `while (_points.first.t < cutoff) _points.removeAt(0)`
    // loop, which was O(N²): every removeAt(0) shifts the whole tail.
    // With the 16 ms tick a busy trail of ~90 points was burning ~8 K
    // shifts per second. Now: one O(N) scan + one O(N) shift, total
    // O(N) per tick.
    var firstAlive = 0;
    while (firstAlive < _points.length && _points[firstAlive].t < cutoff) {
      firstAlive++;
    }
    final pruned = firstAlive > 0;
    if (pruned) _points.removeRange(0, firstAlive);
    if (_points.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (pruned || _points.isNotEmpty) {
      // Always notify while there are points so the painter can
      // re-render them at lower opacity each tick.
      notifyListeners();
    }
  }

  /// Cancel the trail outright (e.g. when the user switches tools).
  void clear() {
    if (_disposed) return;
    _points.clear();
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}

/// Local lasso path tracker — zero Riverpod rebuilds during drawing.
/// At pointer-up the collected path is committed to the provider in one shot.
class LassoPathNotifier extends ChangeNotifier {
  final List<Offset> _points = [];
  bool _active = false;

  List<Offset> get points => _points;
  bool get isActive => _active;

  void start(Offset pos) {
    _points.clear();
    _active = true;
    _points.add(pos);
    notifyListeners();
  }

  void addPoint(Offset pos) {
    _points.add(pos);
    notifyListeners();
  }

  void clear() {
    _points.clear();
    _active = false;
    notifyListeners();
  }
}
