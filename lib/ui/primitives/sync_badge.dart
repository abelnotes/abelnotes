import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import '../theme/hw_theme.dart';
import '../theme/hw_icons.dart';
import 'hw_glass.dart';

/// [localOnly] is a deliberate choice, not a failure: the user asked for
/// this notebook to stay put. Distinct from [offline], which means the
/// remote couldn't be reached and is a problem. [notOnDevice] is its mirror:
/// the notebook is safe on the remote and this device chose not to hold it.
enum HwSyncState { ok, pending, offline, conflict, localOnly, notOnDevice }

/// Cloud icon colored by sync state.
class SyncBadge extends StatelessWidget {
  final HwSyncState state;
  final double size;
  const SyncBadge({super.key, required this.state, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final (icon, color, tooltip) = switch (state) {
      HwSyncState.ok =>
        ('cloud-check', HwTheme.syncOk, l10n.syncOkTooltip),
      HwSyncState.pending =>
        ('cloud-pending', HwTheme.syncPending, l10n.syncPendingTooltip),
      HwSyncState.offline =>
        ('cloud-off', HwTheme.syncPending, l10n.syncOfflineTooltip),
      HwSyncState.conflict =>
        ('cloud-conflict', HwTheme.syncConflict, l10n.syncConflictTooltip),
      HwSyncState.localOnly =>
        ('cloud-off', p.ink2, l10n.syncLocalOnlyTooltip),
      HwSyncState.notOnDevice =>
        ('cloud-download', p.ink2, l10n.syncNotOnDeviceTooltip),
    };
    return Tooltip(
      message: tooltip,
      child: HwIcon(icon, size: size, color: color),
    );
  }
}

/// Notebook cover: spine on the left, soft sheen, title on a bottom scrim.
class NotebookCover extends StatelessWidget {
  final Color color;
  final String title;
  final bool favorite;
  final BackgroundTexture texture;
  final CoverStyle style;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const NotebookCover({
    super.key,
    required this.color,
    required this.title,
    this.favorite = false,
    this.texture = BackgroundTexture.lines,
    this.style = CoverStyle.auto,
    this.width = 200,
    this.height = 260,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    const radius = BorderRadius.only(
      topLeft: Radius.circular(5),
      bottomLeft: Radius.circular(5),
      topRight: Radius.circular(12),
      bottomRight: Radius.circular(12),
    );
    // Fixed insets suit library-sized cards; picker swatches scale them.
    final small = height < 120;
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        child: HwPressable(
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: radius,
                  boxShadow: hwShadow2(p.brightness),
                ),
              ),
              // Spine, with a hairline of light where it meets the board.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 12,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0x24000000),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(5),
                      bottomLeft: Radius.circular(5),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                width: 1,
                child: Container(color: const Color(0x1FFFFFFF)),
              ),
              // Sheen: light from the top-left.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: [0, 0.45, 1],
                        colors: [
                          Color(0x2EFFFFFF),
                          Color(0x00FFFFFF),
                          Color(0x14000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Texture overlay (subtle white pattern)
              if (style == CoverStyle.auto)
                Positioned(
                  left: small ? width * 0.14 : 28,
                  right: small ? width * 0.09 : 18,
                  top: small ? height * 0.15 : 40,
                  bottom: small ? height * 0.19 : 50,
                  // Web paints the alpha in: an Opacity layer per cover is
                  // re-rasterized on every scroll frame there.
                  child: kIsWeb
                      ? CustomPaint(
                          painter: _TexturePainter(texture: texture, alpha: 0.35))
                      : Opacity(
                          opacity: 0.35,
                          child: CustomPaint(
                            painter: _TexturePainter(texture: texture),
                          ),
                        ),
                )
              else
                Positioned(
                  left: 13,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topRight: radius.topRight,
                      bottomRight: radius.bottomRight,
                    ),
                    child: CustomPaint(painter: CoverPatternPainter(style)),
                  ),
                ),
              // Bottom darkening scrim behind the title — pushes the
              // white-text contrast up on the lighter cover swatches
              // (mustard, sage, dusty rose) to clear WCAG AA. The single
              // 0x26 text shadow alone landed white-on-mustard around
              // ~3.5:1 (below 4.5:1).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: small ? height * 0.3 : 80,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x66000000)],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: radius.bottomLeft,
                        bottomRight: radius.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              // Title
              Positioned(
                left: 24,
                right: 18,
                bottom: 18,
                child: _CoverTitle(title),
              ),
              // Favorite star
              if (favorite)
                const Positioned(
                  top: 12,
                  right: 12,
                  child: HwIcon('star-filled',
                      size: 14, color: Color(0xF2FFFFFF)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum BackgroundTexture { lines, grid, dots, blank, cornell }

/// The cover texture that matches a notebook's paper type.
BackgroundTexture coverTextureFor(String paperType) {
  switch (paperType) {
    case 'lined':
    case 'lined_narrow':
    case 'lined_wide':
      return BackgroundTexture.lines;
    case 'grid':
      return BackgroundTexture.grid;
    case 'dotted':
      return BackgroundTexture.dots;
    case 'cornell':
      return BackgroundTexture.cornell;
    default:
      return BackgroundTexture.blank;
  }
}

/// Cover pattern stored in `NotebookMetadata.coverStyle`. [auto] keeps the
/// paper-type hint; keys from a newer version read as [auto].
enum CoverStyle {
  auto('default'),
  plain('plain'),
  pinstripe('pinstripe'),
  diagonal('diagonal'),
  polka('polka'),
  gingham('gingham'),
  waves('waves'),
  label('label'),
  twoTone('two_tone'),
  sheen('sheen');

  final String key;
  const CoverStyle(this.key);

  static CoverStyle fromKey(String? key) =>
      values.firstWhere((s) => s.key == key, orElse: () => auto);
}

/// Paints a [CoverStyle] over the whole cover; sizes are in logical pixels
/// so the pattern keeps its scale on small list swatches.
class CoverPatternPainter extends CustomPainter {
  final CoverStyle style;
  const CoverPatternPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()
      ..color = const Color(0x2EFFFFFF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    switch (style) {
      case CoverStyle.auto:
      case CoverStyle.plain:
        break;
      case CoverStyle.pinstripe:
        for (var x = 6.0; x < w; x += 8) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), line);
        }
        break;
      case CoverStyle.diagonal:
        final band = Paint()
          ..color = const Color(0x1FFFFFFF)
          ..strokeWidth = 5;
        for (var d = -h; d < w; d += 14) {
          canvas.drawLine(Offset(d, h), Offset(d + h, 0), band);
        }
        break;
      case CoverStyle.polka:
        final dot = Paint()..color = const Color(0x38FFFFFF);
        var row = 0;
        for (var y = 8.0; y < h; y += 12, row++) {
          for (var x = row.isEven ? 8.0 : 14.0; x < w; x += 12) {
            canvas.drawCircle(Offset(x, y), 2.2, dot);
          }
        }
        break;
      case CoverStyle.gingham:
        final band = Paint()..color = const Color(0x1AFFFFFF);
        for (var x = 0.0; x < w; x += 16) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 8, h), band);
        }
        for (var y = 0.0; y < h; y += 16) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, 8), band);
        }
        break;
      case CoverStyle.waves:
        final wave = Paint()
          ..color = const Color(0x33FFFFFF)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        for (var y = 10.0; y < h; y += 12) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x < w; x += 12) {
            path.quadraticBezierTo(x + 3, y - 3, x + 6, y);
            path.quadraticBezierTo(x + 9, y + 3, x + 12, y);
          }
          canvas.drawPath(path, wave);
        }
        break;
      case CoverStyle.label:
        final rect = Rect.fromLTWH(w * 0.14, h * 0.18, w * 0.72, h * 0.2);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()..color = const Color(0xD9FFFFFF));
        final ink = Paint()
          ..color = const Color(0x33000000)
          ..strokeWidth = 1;
        for (var i = 1; i <= 2; i++) {
          final y = rect.top + rect.height * i / 3;
          canvas.drawLine(Offset(rect.left + 8, y), Offset(rect.right - 8, y), ink);
        }
        break;
      case CoverStyle.twoTone:
        canvas.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.38),
            Paint()..color = const Color(0x2E000000));
        canvas.drawLine(Offset(0, h * 0.62), Offset(w, h * 0.62),
            Paint()
              ..color = const Color(0x40FFFFFF)
              ..strokeWidth = 1);
        break;
      case CoverStyle.sheen:
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x26000000)],
            ).createShader(Offset.zero & size),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(CoverPatternPainter old) => old.style != style;
}

class _TexturePainter extends CustomPainter {
  final BackgroundTexture texture;
  final double alpha;
  _TexturePainter({required this.texture, this.alpha = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final white = Colors.white.withValues(alpha: alpha);
    final paint = Paint()
      ..color = white
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    // Swatch-sized areas only; library cards keep the original 20px margin.
    final short = math.min(w, h);
    final m = short < 100 ? short * 0.12 : 20.0;
    switch (texture) {
      case BackgroundTexture.lines:
        for (var y = m; y <= h - m; y += (h - 2 * m) / 5) {
          canvas.drawLine(Offset(0, y), Offset(w, y), paint);
        }
        break;
      case BackgroundTexture.grid:
        for (var y = m; y <= h - m; y += (h - 2 * m) / 5) {
          canvas.drawLine(Offset(0, y), Offset(w, y), paint);
        }
        for (var x = m; x <= w - m; x += (w - 2 * m) / 4) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
        }
        break;
      case BackgroundTexture.dots:
        final dot = Paint()..color = white;
        for (var y = m; y <= h - m; y += (h - 2 * m) / 5) {
          for (var x = m; x <= w - m; x += (w - 2 * m) / 4) {
            canvas.drawCircle(Offset(x, y), 1.2, dot);
          }
        }
        break;
      case BackgroundTexture.cornell:
        canvas.drawLine(Offset(w * 0.3, 0), Offset(w * 0.3, h - m), paint);
        canvas.drawLine(
            Offset(0, h - m), Offset(w, h - m), paint);
        break;
      case BackgroundTexture.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) =>
      old.texture != texture || old.alpha != alpha;
}

/// Cover title: shrinks (down to 11) until its longest word fits, so a
/// long single word never breaks mid-word on a narrow phone cover.
class _CoverTitle extends StatelessWidget {
  final String title;
  const _CoverTitle(this.title);

  static const _style = TextStyle(
    color: Color(0xF2FFFFFF),
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.2,
    shadows: [
      Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 4),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Measure with the inherited font, the one the Text below renders in.
      final base = DefaultTextStyle.of(context).style.merge(_style);
      var style = base;
      final words = title.split(RegExp(r'\s+'));
      final longest = words.fold<double>(0, (w, word) {
        final tp = TextPainter(
          text: TextSpan(text: word, style: base),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        return tp.width > w ? tp.width : w;
      });
      if (c.maxWidth.isFinite && longest > c.maxWidth) {
        style = base.copyWith(
            fontSize: (15 * c.maxWidth / longest).clamp(11, 15).toDouble());
      }
      return Text(title,
          maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    });
  }
}
