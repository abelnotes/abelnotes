// Page geometry of the editor viewport: fit scale, centre offset and the
// page <-> screen mapping, in one place.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';

class PageViewTransform {
  const PageViewTransform({
    required this.pageWidth,
    required this.pageHeight,
    required this.canvasSize,
    required this.isScratch,
    required this.zoom,
    required this.pan,
  });

  factory PageViewTransform.of(CanvasState state, Size canvasSize) =>
      PageViewTransform(
        pageWidth: state.currentPage?.width ?? 595,
        pageHeight: state.currentPage?.height ?? 842,
        canvasSize: canvasSize,
        isScratch: state.isScratch,
        zoom: state.zoom,
        pan: state.panOffset,
      );

  final double pageWidth;
  final double pageHeight;
  final Size canvasSize;
  final bool isScratch;
  final double zoom;
  final Offset pan;

  double get _fitScale =>
      min(canvasSize.width / pageWidth, canvasSize.height / pageHeight);

  double get renderScale {
    // Scratch (infinite canvas): fixed 1:1 so a pen stroke stays natural
    // size and the user roams via free pan/zoom — no fit-to-page shrink.
    if (isScratch) return 1.0;
    return _fitScale;
  }

  /// Offset that centres the fitted page inside the viewport. Zero for
  /// scratch mode (the big page isn't fit-centred; panOffset positions it).
  /// MUST stay in lock-step with [CanvasRenderEngine.paint]'s centerOffset.
  Offset get center {
    if (isScratch) return Offset.zero;
    final rs = _fitScale;
    return Offset(
      (canvasSize.width - pageWidth * rs) / 2,
      (canvasSize.height - pageHeight * rs) / 2,
    );
  }

  Offset toPage(Offset localPos) {
    final renderScale = this.renderScale;
    final center = this.center;
    final unPanned = localPos - pan - center * zoom;
    final unZoomed = unPanned / zoom;
    return unZoomed / renderScale;
  }

  Offset toScreen(Offset pagePos) {
    final renderScale = this.renderScale;
    final center = this.center;
    final scaled = pagePos * renderScale;
    return scaled * zoom + pan + center * zoom;
  }

  // Page edges in screen x, for paged notebooks only (scratch has no
  // page-to-page swipe). [panX] is the horizontal pan to use.
  double pageRightScreen(double panX) {
    final scaledW = pageWidth * _fitScale;
    final centerOffsetX = (canvasSize.width - scaledW) / 2;
    return (scaledW * zoom) + panX + (centerOffsetX * zoom);
  }

  double pageLeftScreen(double panX) {
    final scaledW = pageWidth * _fitScale;
    final centerOffsetX = (canvasSize.width - scaledW) / 2;
    return panX + (centerOffsetX * zoom);
  }
}
