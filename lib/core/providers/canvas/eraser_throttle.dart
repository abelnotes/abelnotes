import 'dart:async';
import 'dart:ui';

import 'package:uuid/uuid.dart';

import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/features/canvas/data/element_geometry.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart'
    show shapeBodyContains;
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Per-StrokeData bounding-box cache used by the eraser hit-test (weak-keyed:
/// lives as long as the stroke), so a dense page is not walked point by point.
final Expando<Rect> _strokeBboxCache = Expando<Rect>();

/// Eraser hit-testing, throttled: erasures pile up in a pending page that
/// reaches `state` at most every 16 ms, or at once on pointer-up. Without it
/// every pointer event (60-120 Hz) rebuilt the 215-page map and the Picture cache.
class EraserThrottle {
  EraserThrottle(this._core);

  final CanvasCore _core;
  PageData? _pendingPage;
  String? _pendingFileName;
  Timer? _flushTimer;
  DateTime _lastFlushAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// One flush per vsync (60 Hz): slower feels choppy, each flush stays cheap.
  static const Duration _flushInterval = Duration(milliseconds: 16);

  /// Last position where [eraseAt] walked the content list; movement below
  /// [_radiusFraction] x radius is skipped (sub-mm samples at 120 Hz).
  Offset _lastAtPos = const Offset(-1e9, -1e9);

  /// Start of the current gesture: the radius grows the longer it is held.
  DateTime? _gestureStart;

  /// One undo entry per gesture, pushed on its first flush.
  bool _undoPushed = false;

  /// 0.1 still skips noise but does not stutter slow drags on graphics tablets.
  static const double _radiusFraction = 0.1;

  bool get hasPending => _pendingPage != null;

  /// Starts a gesture: fresh undo entry, no distance throttle, growth clock at zero.
  void beginGesture() {
    _undoPushed = false;
    _lastAtPos = const Offset(-1e9, -1e9);
    _gestureStart = DateTime.now();
  }

  /// Pointer-up: lands any throttled erasure and resets the growth clock.
  void endGesture() {
    if (_pendingPage != null) flush();
    _gestureStart = null;
  }

  /// Cancels the gesture without committing what is pending.
  void cancelGesture() {
    discard();
    _undoPushed = false;
    _gestureStart = null;
  }

  /// Drops the pending page and its timer.
  void discard() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingPage = null;
    _pendingFileName = null;
  }

  void eraseAt(Offset position) {
    if (_core.state == null) return;
    final s = _core.state!;
    // Base radius from the user's eraser-size pref, scaled up after a
    // sustained gesture. Curve: starts at 1.0, ramps to ~2.5 over 5 s
    // of continuous drawing, then caps. The user keeps moving →
    // effective radius keeps growing, so "wipe everything in this
    // region" works without flipping size from the popup.
    final base = s.toolSettings.eraserRadius;
    final startedAt = _gestureStart;
    double growth = 1.0;
    if (startedAt != null) {
      final secs = DateTime.now().difference(startedAt).inMilliseconds / 1000;
      // Linear up to 5 s, capped at 2.5×. Gesture under ~0.8 s leaves
      // growth ≈ 1.05 — imperceptible, doesn't surprise the user on
      // quick taps.
      growth = (1.0 + secs * 0.30).clamp(1.0, 2.5);
    }
    final eraseRadius = base * growth;
    // Sub-radius movement check: any element a closer-spaced previous
    // sample might erase is also reachable from this near-identical
    // position, so skip the O(elements × points) scan entirely.
    final dx = position.dx - _lastAtPos.dx;
    final dy = position.dy - _lastAtPos.dy;
    final movedSq = dx * dx + dy * dy;
    final thresholdSq = (eraseRadius * _radiusFraction) *
        (eraseRadius * _radiusFraction);
    if (movedSq < thresholdSq) return;
    _lastAtPos = position;

    // Now that we know we're going to do real erase work, push the
    // cursor visualisation to state. Throttling this with the same
    // dist-check as the erase compute means the cursor visibly moves
    // ~30 Hz instead of 120 Hz, but only saves Riverpod fan-out work
    // — at radius * 0.3 movement thresholds the cursor still tracks
    // the pointer smoothly to the eye.
    _core.state = s.copyWith(eraserCursorPos: position);
    final s2 = _core.state!;

    final fileName = s2.currentPageFileName;
    // Use the in-progress pending page as base if we have one — otherwise
    // each event would re-erase from the original (pre-gesture) page and
    // wipe out earlier erasures within the throttle window.
    final page =
        (_pendingPage != null && _pendingFileName == fileName)
            ? _pendingPage!
            : s.currentPage;
    if (page == null) return;

    final isStrokeEraser = s.currentTool == CanvasTool.eraserStroke;

    final newContent = <ContentElement>[];
    bool changed = false;

    // Avoid `element.map(stroke:_, text:_, image:_, shape:_)` per
    // element — that's 4 closure allocations per call, twice per
    // element below = 8 closures × 200 elements × ~30 Hz ≈ 48 k
    // closure allocs/sec of pure GC pressure during a drag. Replace
    // with `is` checks on the runtime subtype which is zero-alloc.
    for (final element in page.layers.content) {
      bool shouldRemoveWhole = false;

      // Check non-stroke elements (text, symbols, shapes).
      //
      // Text, symbols and typeset math are ATOMIC — there's no way to
      // pixel-erase into them — so both erasers use the same test: the
      // element goes when the cursor touches its box. The standard eraser
      // used to test the box EDGES only, which meant scrubbing right
      // across the middle of a paragraph did nothing at all and the user
      // had to hunt for the border.
      if (element is TextElement) {
        final t = element.data;
        final rect = Rect.fromLTWH(t.x, t.y, t.width, t.height);
        if (rect.inflate(eraseRadius).contains(position)) {
          shouldRemoveWhole = true;
        }
      } else if (element is ImageElement) {
        final img = element.data;
        if (img.assetPath.startsWith('symbol_')) {
          final rect = Rect.fromLTWH(img.x, img.y, img.width, img.height);
          if (rect.inflate(eraseRadius).contains(position)) {
            shouldRemoveWhole = true;
          }
        }
      } else if (element is ShapeElement && isStrokeEraser) {
        final sh = element.data;
        final rect = Rect.fromPoints(
          Offset(sh.x1, sh.y1),
          Offset(sh.x2, sh.y2),
        );
        // Bbox is only a cheap reject: a diagonal line's bbox is mostly
        // empty space, so a bbox-contains test erased lines the cursor
        // was nowhere near. Confirm the hit against the sampled outline.
        // Rotated shapes skip the bbox gate — their outline can extend
        // outside the axis-aligned x1..x2/y1..y2 rect.
        if (sh.rotation != 0 ||
            rect.inflate(eraseRadius).contains(position)) {
          // A filled shape's interior is ink too: scrubbing anywhere
          // inside it deletes the element, same as touching the outline.
          shouldRemoveWhole =
              (sh.fillColor != null && shapeBodyContains(sh, position)) ||
                  shapeOutlineWithin(sh, position, eraseRadius);
        }
      } else if (element is MathElement) {
        // Typeset math is an atomic object (like text): delete the whole
        // equation on hit; never pixel-erase into it.
        final m = element.data;
        final rect = Rect.fromLTWH(m.x, m.y, m.width, m.height);
        if (rect.inflate(eraseRadius).contains(position)) {
          shouldRemoveWhole = true;
        }
      }

      if (shouldRemoveWhole) {
        changed = true;
        continue;
      }

      // For strokes: stroke eraser removes entire stroke, standard eraser
      // splits it into segments by erasing only the touched points.
      // For shapes (standard eraser only): decompose outline into sampled
      // points and apply the same splitting logic, so only the touched
      // portion is erased.
      bool handled = false;
      // Same closure-free pattern: replace `element.map(stroke:_, ...)`
      // with a typed dispatch.
      if (element is StrokeElement) {
        final stroke = element;
        handled = true;

        // BBOX FAST PATH — most strokes on a dense page are nowhere
        // near the eraser cursor, so walking all 80 points just to
        // discover that is wasted work. Cache the stroke's bbox via
        // Expando the first time we see it.
        var bbox = _strokeBboxCache[stroke.data];
        if (bbox == null) {
          double minX = double.infinity, minY = double.infinity;
          double maxX = -double.infinity, maxY = -double.infinity;
          for (final p in stroke.data.points) {
            if (p.x < minX) minX = p.x;
            if (p.x > maxX) maxX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.y > maxY) maxY = p.y;
          }
          if (minX == double.infinity) {
            newContent.add(element);
            continue;
          }
          bbox = Rect.fromLTRB(minX, minY, maxX, maxY);
          _strokeBboxCache[stroke.data] = bbox;
        }
        if (!bbox.inflate(eraseRadius).contains(position)) {
          newContent.add(element);
          continue;
        }

        final r2 = eraseRadius * eraseRadius;
        if (isStrokeEraser) {
          bool hit = false;
          for (final point in stroke.data.points) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < r2) {
              hit = true;
              break;
            }
          }
          if (hit) {
            changed = true;
          } else {
            newContent.add(element);
          }
        } else {
          bool anyTouched = false;
          for (final point in stroke.data.points) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < r2) {
              anyTouched = true;
              break;
            }
          }
          if (!anyTouched) {
            newContent.add(element);
            continue;
          }
          final segments = <List<StrokePoint>>[];
          var currentSegment = <StrokePoint>[];
          for (final point in stroke.data.points) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < r2) {
              if (currentSegment.length >= 2) {
                segments.add(currentSegment);
              }
              currentSegment = [];
              changed = true;
            } else {
              currentSegment.add(point);
            }
          }
          if (currentSegment.length >= 2) {
            segments.add(currentSegment);
          }
          if (segments.isEmpty) {
            changed = true;
            continue;
          }
          if (segments.length == 1 &&
              segments[0].length == stroke.data.points.length) {
            newContent.add(element);
            continue;
          }
          for (final seg in segments) {
            newContent.add(ContentElement.stroke(
              id: const Uuid().v4(),
              zIndex: stroke.zIndex,
              data: StrokeData(
                points: seg,
                toolType: stroke.data.toolType,
                color: stroke.data.color,
                baseWidth: stroke.data.baseWidth,
                isHighlighter: stroke.data.isHighlighter,
                opacity: stroke.data.opacity,
                timestamp: stroke.data.timestamp,
              ),
            ));
          }
        }
      } else if (element is ShapeElement && !isStrokeEraser) {
        final sh = element;
        handled = true;

        // BBOX FAST PATH — same reason as the stroke branch above: without
        // it every shape on the page got its outline re-sampled (dozens to
        // hundreds of points for an ellipse) on every erase event, however
        // far from the cursor it was. Rotated shapes skip the gate; their
        // outline can fall outside the axis-aligned x1..x2/y1..y2 rect.
        final shBounds = Rect.fromPoints(
          Offset(sh.data.x1, sh.data.y1),
          Offset(sh.data.x2, sh.data.y2),
        );
        if (sh.data.rotation == 0 &&
            !shBounds.inflate(eraseRadius).contains(position)) {
          newContent.add(element);
          continue;
        }

        // A filled shape can't be nibbled: the surviving pieces are plain
        // strokes and there's nowhere to keep the fill, so grazing the
        // border used to silently delete the whole filled area. Treat a
        // filled shape as atomic for this eraser too — outline OR interior
        // contact removes it, which is also what the user expects when
        // scrubbing across a solid blob.
        if (sh.data.fillColor != null) {
          if (shapeBodyContains(sh.data, position) ||
              shapeOutlineWithin(sh.data, position, eraseRadius)) {
            changed = true;
            continue;
          }
          newContent.add(element);
          continue;
        }

        final sampledEdges = shapeToSampledEdges(sh.data, eraseRadius * 0.5);
        bool anyErased = false;
        final survivingStrokes = <ContentElement>[];

        for (final edgePoints in sampledEdges) {
          final segments = <List<StrokePoint>>[];
          var currentSeg = <StrokePoint>[];

          for (final point in edgePoints) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < eraseRadius * eraseRadius) {
              if (currentSeg.length >= 2) segments.add(currentSeg);
              currentSeg = [];
              anyErased = true;
            } else {
              currentSeg.add(point);
            }
          }
          if (currentSeg.length >= 2) segments.add(currentSeg);

          for (final seg in segments) {
            survivingStrokes.add(ContentElement.stroke(
              id: const Uuid().v4(),
              zIndex: sh.zIndex,
              data: StrokeData(
                points: seg,
                // Carry the shape's ink type over. Hardcoding opaque
                // ballpoint turned what was left of a highlighter-drawn
                // shape into solid ink the moment the eraser touched it.
                toolType:
                    sh.data.isHighlighter ? 'highlighter' : 'ballpoint',
                color: sh.data.strokeColor,
                baseWidth: sh.data.strokeWidth,
                isHighlighter: sh.data.isHighlighter,
                opacity: 1.0,
              ),
            ));
          }
        }

        if (anyErased) {
          changed = true;
          newContent.addAll(survivingStrokes);
        } else {
          newContent.add(element);
        }
      }

      if (!handled) {
        newContent.add(element);
      }
    }

    if (!changed) return;

    final updatedPage = _core.pageWithContent(page, newContent);

    // Stash the latest computed page locally; commit to `state` at most
    // every [_flushInterval] (or immediately on pointer-up via
    // [flush]). This drops the ~60-120 Hz state cascade
    // (Picture rebuild + chrome notify + Map<String,PageData>.from
    // copy of 215 entries) down to ~30 Hz while keeping erase visually
    // smooth.
    _pendingPage = updatedPage;
    _pendingFileName = fileName;
    final elapsed = DateTime.now().difference(_lastFlushAt);
    if (elapsed >= _flushInterval) {
      flush();
    } else {
      _flushTimer?.cancel();
      _flushTimer =
          Timer(_flushInterval - elapsed, flush);
    }
  }

  /// Apply the buffered eraser changes to `state`. Called from either
  /// the throttle Timer in [eraseAt] or directly on pointer-up by
  /// [endStroke] so the final erase state always lands.
  void flush() {
    if (_core.isDisposed) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    final pending = _pendingPage;
    final fn = _pendingFileName;
    if (pending == null || fn == null || _core.state == null) {
      _pendingPage = null;
      _pendingFileName = null;
      return;
    }
    final s = _core.state!;
    if (s.currentPageFileName != fn) {
      // User flipped pages mid-erase; drop the buffer.
      _pendingPage = null;
      _pendingFileName = null;
      return;
    }

    // Push undo only once per eraser gesture (first flush of the burst).
    PageData? undoOf;
    if (!_undoPushed) {
      // Use the original pre-gesture page from `s.pages[fn]`, NOT the
      // pending page (which has erasures already applied).
      undoOf = s.pages[fn];
      _undoPushed = true;
    }

    _core.commitPageEdit(s, fn, pending, undoOf: undoOf);

    _pendingPage = null;
    _pendingFileName = null;
    _lastFlushAt = DateTime.now();
  }
}
