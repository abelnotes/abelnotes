// ═══════════════════════════════════════════════════════════════
//  canvas_crop_dialog.dart
//
//  Image crop dialog with draggable corner handles.
//  Extracted from canvas_screen.dart.
// ═══════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Modal dialog that lets the user drag a crop rectangle over an image.
/// [onCrop] is called with the resulting rect in normalized 0..1 coords.
class CropDialog extends StatefulWidget {
  final ui.Image image;
  final ImageData imageData;
  final ValueChanged<Rect> onCrop;

  const CropDialog({
    super.key,
    required this.image,
    required this.imageData,
    required this.onCrop,
  });

  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  // Crop rect in normalized 0..1 coords
  double _left = 0, _top = 0, _right = 1, _bottom = 1;
  static const _minCrop = 0.05;

  @override
  Widget build(BuildContext context) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fit image in dialog (max 500x500), but never let the total dialog
          // width (image + 48px horizontal padding) exceed the available space.
          const maxSize = 500.0;
          final maxDisplayW = max(0.0, (constraints.maxWidth - 32) - 48);
          final scale = min(
            min(maxSize / imgW, maxSize / imgH),
            maxDisplayW / imgW,
          );
          final displayW = imgW * scale;
          final displayH = imgH * scale;

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: displayW + 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.of(context).cropTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: displayW,
                    height: displayH,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        setState(() {
                          final dx = d.delta.dx / displayW;
                          final dy = d.delta.dy / displayH;
                          _left = (_left + dx).clamp(0.0, _right - _minCrop);
                          _top = (_top + dy).clamp(0.0, _bottom - _minCrop);
                          _right = (_right + dx).clamp(_left + _minCrop, 1.0);
                          _bottom = (_bottom + dy).clamp(_top + _minCrop, 1.0);
                        });
                      },
                      child: CustomPaint(
                        painter: CropPainter(
                          image: widget.image,
                          cropLeft: _left,
                          cropTop: _top,
                          cropRight: _right,
                          cropBottom: _bottom,
                        ),
                        size: Size(displayW, displayH),
                        child: Stack(
                          children: [
                            _cropHandle(displayW, displayH, 'tl'),
                            _cropHandle(displayW, displayH, 'tr'),
                            _cropHandle(displayW, displayH, 'bl'),
                            _cropHandle(displayW, displayH, 'br'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(AppLocalizations.of(context).cropCancel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onCrop(Rect.fromLTRB(_left, _top, _right, _bottom));
                            Navigator.pop(context);
                          },
                          child: Text(AppLocalizations.of(context).cropConfirm),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cropHandle(double displayW, double displayH, String corner) {
    double left, top;
    switch (corner) {
      case 'tl': left = _left * displayW - 8; top = _top * displayH - 8;
      case 'tr': left = _right * displayW - 8; top = _top * displayH - 8;
      case 'bl': left = _left * displayW - 8; top = _bottom * displayH - 8;
      case 'br': left = _right * displayW - 8; top = _bottom * displayH - 8;
      default: return const SizedBox.shrink();
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            final dx = d.delta.dx / displayW;
            final dy = d.delta.dy / displayH;
            switch (corner) {
              case 'tl':
                _left = (_left + dx).clamp(0.0, _right - _minCrop);
                _top = (_top + dy).clamp(0.0, _bottom - _minCrop);
              case 'tr':
                _right = (_right + dx).clamp(_left + _minCrop, 1.0);
                _top = (_top + dy).clamp(0.0, _bottom - _minCrop);
              case 'bl':
                _left = (_left + dx).clamp(0.0, _right - _minCrop);
                _bottom = (_bottom + dy).clamp(_top + _minCrop, 1.0);
              case 'br':
                _right = (_right + dx).clamp(_left + _minCrop, 1.0);
                _bottom = (_bottom + dy).clamp(_top + _minCrop, 1.0);
            }
          });
        },
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// CustomPainter that draws the image with a dimmed overlay outside the crop rect.
class CropPainter extends CustomPainter {
  final ui.Image image;
  final double cropLeft, cropTop, cropRight, cropBottom;

  CropPainter({
    required this.image,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint()..filterQuality = FilterQuality.low);

    // Dim outside crop area
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final cropRect = Rect.fromLTRB(
      cropLeft * size.width,
      cropTop * size.height,
      cropRight * size.width,
      cropBottom * size.height,
    );
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, cropRect.top), dimPaint);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.bottom, size.width, size.height), dimPaint);
    canvas.drawRect(Rect.fromLTRB(0, cropRect.top, cropRect.left, cropRect.bottom), dimPaint);
    canvas.drawRect(Rect.fromLTRB(cropRect.right, cropRect.top, size.width, cropRect.bottom), dimPaint);

    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CropPainter old) =>
      cropLeft != old.cropLeft || cropTop != old.cropTop ||
      cropRight != old.cropRight || cropBottom != old.cropBottom;
}
