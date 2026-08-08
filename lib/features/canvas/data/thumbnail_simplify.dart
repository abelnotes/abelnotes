// ═══════════════════════════════════════════════════════════════
//  thumbnail_simplify.dart
//
//  Scale-aware stroke simplification for page previews.
// ═══════════════════════════════════════════════════════════════

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Preview detail limit, in DEVICE pixels. Below this the rendered-pixel
/// error against a full-detail render stops improving while cost keeps rising.
const double _kPreviewDetailPx = 1.5;

/// Strips ink detail a preview cannot show.
///
/// Previews are drawn at a *fit* scale, so a free-sketch page (6000×6000)
/// lands in a ~110 px grid tile at ~0.018×, where the stylus's ~6-page-unit
/// point spacing is far below one pixel. The render engine's adaptive
/// interpolation cannot absorb that: it only chooses how many segments go
/// *between* two points, and is already pinned at its 2-segment floor. So drop
/// the points themselves.
///
/// [devicePixelsPerUnit] is how many device pixels one page unit occupies —
/// `zoom * baseScale * devicePixelRatio`. At one or more, no ink is sub-pixel
/// and [page] comes back unchanged, by identity, so callers keep sharing the
/// render engine's picture cache. The main canvas is always in that regime.
///
/// Ink here is thinner than a pixel, so its darkness comes from the coverage
/// of overlapping sub-pixel segments and dropping points lightens it slightly
/// (~1% mean). Do not compensate with a minimum on-screen stroke width: every
/// floor from 0.5 to 1.4 device px overshoots into visibly darker ink, six to
/// twelve times further off than leaving it alone.
///
/// Memoised per (page identity, threshold).
PageData simplifyForPreview(PageData page, double devicePixelsPerUnit) {
  if (!devicePixelsPerUnit.isFinite || devicePixelsPerUnit <= 0) return page;
  // One page unit >= one device pixel: nothing is sub-pixel, leave it alone.
  if (devicePixelsPerUnit >= 1.0) return page;

  final minDist = _kPreviewDetailPx / devicePixelsPerUnit;

  final bucket = minDist.round();
  final cached = _memo[page];
  if (cached != null && cached.bucket == bucket) return cached.page;

  final simplified = _simplify(page, bucket.toDouble());
  _memo[page] = _Memo(bucket, simplified);
  return simplified;
}

PageData _simplify(PageData page, double minDist) {
  final minDistSq = minDist * minDist;
  final content = <ContentElement>[];
  var changed = false;

  for (final element in page.layers.content) {
    if (element is! StrokeElement) {
      content.add(element);
      continue;
    }
    final points = element.data.points;
    if (points.length <= 2) {
      content.add(element);
      continue;
    }
    // Always keep the first and last point so a stroke never shrinks away to
    // nothing and its end caps stay put.
    final kept = <StrokePoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final dx = points[i].x - kept.last.x;
      final dy = points[i].y - kept.last.y;
      if (dx * dx + dy * dy >= minDistSq) kept.add(points[i]);
    }
    kept.add(points.last);

    if (kept.length == points.length) {
      content.add(element);
      continue;
    }
    changed = true;
    content.add(ContentElement.stroke(
      id: element.id,
      zIndex: element.zIndex,
      data: element.data.copyWith(points: kept),
    ));
  }

  if (!changed) return page;
  return page.copyWith(layers: page.layers.copyWith(content: content));
}

class _Memo {
  final int bucket;
  final PageData page;
  const _Memo(this.bucket, this.page);
}

/// Weak-keyed: a simplified copy dies with the PageData it was derived from.
final Expando<_Memo> _memo = Expando<_Memo>();
