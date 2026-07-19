import 'package:flutter/material.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import '../theme/hw_theme.dart';
import '../theme/hw_icons.dart';

enum HwSyncState { ok, pending, offline, conflict }

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
      HwSyncState.offline => ('cloud-off', p.ink3, l10n.syncOfflineTooltip),
      HwSyncState.conflict =>
        ('cloud-conflict', HwTheme.syncConflict, l10n.syncConflictTooltip),
    };
    return Tooltip(
      message: tooltip,
      child: HwIcon(icon, size: size, color: color),
    );
  }
}

/// Notebook cover drawn as a tilted card with binding shadow.
/// Matches the design's inset-shadow trick to fake a binding.
class NotebookCover extends StatelessWidget {
  final Color color;
  final String title;
  final bool favorite;
  final BackgroundTexture texture;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const NotebookCover({
    super.key,
    required this.color,
    required this.title,
    this.favorite = false,
    this.texture = BackgroundTexture.lines,
    this.width = 200,
    this.height = 260,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    const radius = BorderRadius.only(
      topLeft: Radius.circular(4),
      bottomLeft: Radius.circular(4),
      topRight: Radius.circular(10),
      bottomRight: Radius.circular(10),
    );
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: radius,
                  boxShadow: hwShadow2(p.brightness),
                ),
              ),
              // Binding shadow (left inner edge)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 12,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0x4D000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
              // Binding line
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                width: 1,
                child: Container(color: const Color(0x26000000)),
              ),
              // Texture overlay (subtle white pattern)
              Positioned(
                left: 28,
                right: 18,
                top: 40,
                bottom: 50,
                child: Opacity(
                  opacity: 0.35,
                  child: CustomPaint(
                    painter: _TexturePainter(texture: texture),
                  ),
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
                height: 80,
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
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xF2FFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15,
                    height: 1.2,
                    shadows: [
                      Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 4),
                    ],
                  ),
                ),
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

class _TexturePainter extends CustomPainter {
  final BackgroundTexture texture;
  _TexturePainter({required this.texture});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    switch (texture) {
      case BackgroundTexture.lines:
        for (var y = 20.0; y <= h - 20; y += (h - 40) / 5) {
          canvas.drawLine(Offset(0, y), Offset(w, y), paint);
        }
        break;
      case BackgroundTexture.grid:
        for (var y = 20.0; y <= h - 20; y += (h - 40) / 5) {
          canvas.drawLine(Offset(0, y), Offset(w, y), paint);
        }
        for (var x = 20.0; x <= w - 20; x += (w - 40) / 4) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
        }
        break;
      case BackgroundTexture.dots:
        final dot = Paint()..color = Colors.white;
        for (var y = 20.0; y <= h - 20; y += (h - 40) / 5) {
          for (var x = 20.0; x <= w - 20; x += (w - 40) / 4) {
            canvas.drawCircle(Offset(x, y), 1.2, dot);
          }
        }
        break;
      case BackgroundTexture.cornell:
        canvas.drawLine(Offset(w * 0.3, 0), Offset(w * 0.3, h - 20), paint);
        canvas.drawLine(
            Offset(0, h - 20), Offset(w, h - 20), paint);
        break;
      case BackgroundTexture.blank:
        break;
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) => old.texture != texture;
}
