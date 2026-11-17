// Reviewing one kept sample: the ink beside what was found in it. A wrong part
// is tapped and corrected or removed, a missed one is boxed by dragging.

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/primitives/scrollable_sheet.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

import 'donation_sample.dart';
import 'donation_store.dart';

String donationSymbolName(AppLocalizations l, String symbol) => switch (symbol) {
      'resistor' => l.symResistor,
      'capacitor' => l.symCapacitor,
      'capacitor.polarized' => l.symCapacitorPolarized,
      'inductor' => l.symInductor,
      'diode' => l.symDiode,
      'voltage.dc' => l.symVoltageDc,
      'voltage.ac' => l.symVoltageAc,
      'voltage.battery' => l.symBattery,
      'current_source' => l.symCurrentSource,
      'transistor.bjt' => l.symBjt,
      'transistor.fet' => l.symFet,
      'opamp' => l.symOpamp,
      'ic' => l.symIc,
      'transformer' => l.symTransformer,
      'switch' => l.symSwitch,
      'gnd' => l.symGnd,
      'vss' => l.symVss,
      'junction' => l.symJunction,
      'crossover' => l.symCrossover,
      'terminal' => l.symTerminal,
      'arrow' => l.symArrow,
      'text' => l.symText,
      _ => symbol,
    };

/// Maps sample units to a widget of [size], centred with a margin, then
/// zoomed by [zoom] and moved by [pan] (view pixels).
class SampleFit {
  SampleFit(DonationSample s, Size size, {double margin = 16, double zoom = 1, Offset pan = Offset.zero}) {
    final w = s.width, h = s.height;
    final fit = math.max(1e-6, math.min((size.width - 2 * margin) / w, (size.height - 2 * margin) / h));
    scale = fit * zoom;
    dx = (size.width - w * fit) / 2 * zoom + pan.dx;
    dy = (size.height - h * fit) / 2 * zoom + pan.dy;
  }
  late final double scale, dx, dy;

  Offset toView(double x, double y) => Offset(dx + x * scale, dy + y * scale);
  Offset toSample(Offset v) => Offset((v.dx - dx) / scale, (v.dy - dy) / scale);
}

class SamplePainter extends CustomPainter {
  SamplePainter(this.sample, this.palette, this.l10n,
      {this.labels = true, this.draft, this.zoom = 1, this.pan = Offset.zero});

  final DonationSample sample;
  final HwPalette palette;
  final AppLocalizations l10n;
  final bool labels;

  /// A box being dragged out, in view coordinates.
  final Rect? draft;
  final double zoom;
  final Offset pan;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = SampleFit(sample, size, margin: labels ? 24 : 6, zoom: zoom, pan: pan);
    final ink = Paint()
      ..color = palette.ink0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      // The detector sees ~3.3 px strokes at this scale.
      ..strokeWidth = (3.3 * fit.scale).clamp(0.8, 4.0);
    for (final s in sample.strokes) {
      final path = Path();
      for (var i = 0; i + 3 < s.length; i += 4) {
        final o = fit.toView(s[i], s[i + 1]);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      if (s.length == 4) {
        final o = fit.toView(s[0], s[1]);
        canvas.drawCircle(o, ink.strokeWidth / 2, ink..style = PaintingStyle.fill);
        ink.style = PaintingStyle.stroke;
      } else {
        canvas.drawPath(path, ink);
      }
    }
    for (final part in sample.parts) {
      final changed = part.detected != part.symbol;
      final color = changed ? HwTheme.syncOk : palette.accent;
      final r = Rect.fromPoints(fit.toView(part.x, part.y), fit.toView(part.x + part.w, part.y + part.h));
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()
            ..color = color.withValues(alpha: 0.08)
            ..style = PaintingStyle.fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = labels ? 1.5 : 1);
      if (!labels) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: donationSymbolName(l10n, part.symbol),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.onAccent)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(40, r.width + 40));
      final above = r.top - tp.height - 4;
      // No room above the box: the label goes under it instead of off-canvas.
      // Kept inside the right edge too.
      final left = math.max(0.0, math.min(r.left, size.width - tp.width - 8));
      final chip = Rect.fromLTWH(left, above >= 0 ? above : r.bottom, tp.width + 8, tp.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(3)), Paint()..color = color);
      tp.paint(canvas, Offset(chip.left + 4, chip.top + 2));
    }
    if (draft != null) {
      canvas.drawRect(
          draft!,
          Paint()
            ..color = HwTheme.syncOk
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(SamplePainter old) =>
      old.sample != sample || old.draft != draft || old.palette != palette || old.zoom != zoom || old.pan != pan;
}

/// Picks the symbol of a part; returns '' to remove it, null when dismissed.
Future<String?> pickDonationSymbol(BuildContext context, {String? current}) {
  final l10n = AppLocalizations.of(context);
  final p = HwThemeScope.of(context);
  final names = [...kDonationSymbols]
    ..sort((a, b) => donationSymbolName(l10n, a).compareTo(donationSymbolName(l10n, b)));
  return showScrollableSheet<String>(
    context: context,
    backgroundColor: p.paper0,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(l10n.donPickSymbol, style: HwType.headline.copyWith(color: p.ink0)),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: HwTheme.syncConflict),
              title: Text(l10n.donRemovePart, style: const TextStyle(color: HwTheme.syncConflict)),
              onTap: () => Navigator.pop(ctx, ''),
            ),
          for (final s in names)
            ListTile(
              dense: true,
              title: Text(donationSymbolName(l10n, s), style: TextStyle(color: p.ink0)),
              trailing: s == current ? HwIcon('check', size: 16, color: p.accent) : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class DonationReviewPage extends ConsumerStatefulWidget {
  const DonationReviewPage({super.key, required this.sampleId});
  final String sampleId;

  @override
  ConsumerState<DonationReviewPage> createState() => _DonationReviewPageState();
}

class _DonationReviewPageState extends ConsumerState<DonationReviewPage> {
  DonationSample? _sample;
  Offset? _dragStart;
  Rect? _draft;

  // One finger drags out a box; two fingers (or the wheel) zoom and pan, so
  // small parts stay reachable on a phone.
  double _zoom = 1;
  Offset _pan = Offset.zero;
  bool _zooming = false;
  double _zoomAtStart = 1;
  Offset _panAtStart = Offset.zero, _focalAtStart = Offset.zero;

  void _zoomTo(double zoom, Offset focal, {double? from, Offset? panFrom, Offset? focalFrom}) {
    final z0 = from ?? _zoom;
    final p0 = panFrom ?? _pan;
    final f0 = focalFrom ?? focal;
    final z = zoom.clamp(1.0, 8.0);
    // The content point under the first focal stays under the finger.
    final content = (f0 - p0) / z0;
    setState(() {
      _zoom = z;
      _pan = z == 1 ? Offset.zero : focal - content * z;
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _zooming = d.pointerCount > 1;
    _zoomAtStart = _zoom;
    _panAtStart = _pan;
    _focalAtStart = d.localFocalPoint;
    if (!_zooming) {
      setState(() {
        _dragStart = d.localFocalPoint;
        _draft = Rect.fromPoints(d.localFocalPoint, d.localFocalPoint);
      });
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!_zooming && d.pointerCount > 1) {
      // A second finger arrived: this is a zoom, not a box.
      _zooming = true;
      _zoomAtStart = _zoom;
      _panAtStart = _pan;
      _focalAtStart = d.localFocalPoint;
      setState(() => _draft = null);
    }
    if (_zooming) {
      _zoomTo(_zoomAtStart * d.scale, d.localFocalPoint,
          from: _zoomAtStart, panFrom: _panAtStart, focalFrom: _focalAtStart);
    } else if (_dragStart != null) {
      setState(() => _draft = Rect.fromPoints(_dragStart!, d.localFocalPoint));
    }
  }

  void _onScaleEnd(SampleFit fit) {
    final r = _draft;
    setState(() {
      _draft = null;
      _dragStart = null;
    });
    if (!_zooming && r != null) _addBox(fit, r);
    _zooming = false;
  }

  @override
  void initState() {
    super.initState();
    _sample = ref.read(donationProvider).queue.where((s) => s.id == widget.sampleId).firstOrNull;
  }

  void _edit(List<DonationPart> parts) {
    final s = _sample!.copyWith(parts: parts, reviewed: false);
    setState(() => _sample = s);
    ref.read(donationProvider.notifier).update(s);
  }

  /// The smallest box under [v]: nested parts stay reachable.
  int? _hit(SampleFit fit, Offset v) {
    final pt = fit.toSample(v);
    final pad = 8 / fit.scale;
    int? best;
    var bestArea = double.infinity;
    final parts = _sample!.parts;
    for (var i = 0; i < parts.length; i++) {
      final q = parts[i];
      if (pt.dx < q.x - pad || pt.dx > q.x + q.w + pad || pt.dy < q.y - pad || pt.dy > q.y + q.h + pad) continue;
      final area = q.w * q.h;
      if (area < bestArea) {
        best = i;
        bestArea = area;
      }
    }
    return best;
  }

  Future<void> _tap(SampleFit fit, Offset v) async {
    final i = _hit(fit, v);
    if (i == null) return;
    final part = _sample!.parts[i];
    final pick = await pickDonationSymbol(context, current: part.symbol);
    if (pick == null || !mounted) return;
    final parts = [..._sample!.parts];
    pick.isEmpty ? parts.removeAt(i) : parts[i] = part.withSymbol(pick);
    _edit(parts);
  }

  Future<void> _addBox(SampleFit fit, Rect view) async {
    final a = fit.toSample(view.topLeft), b = fit.toSample(view.bottomRight);
    final r = Rect.fromPoints(a, b);
    // A short drag is a slip, not a part.
    if (r.width < 8 || r.height < 8) return;
    final pick = await pickDonationSymbol(context);
    if (pick == null || pick.isEmpty || !mounted) return;
    _edit([..._sample!.parts, DonationPart(pick, r.left, r.top, r.width, r.height)]);
  }

  void _discard() {
    ref.read(donationProvider.notifier).remove(widget.sampleId);
    Navigator.of(context).pop();
  }

  void _markReviewed() {
    ref.read(donationProvider.notifier).update(_sample!.copyWith(reviewed: true));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final s = _sample;
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: s == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(children: [
                      IconButton(
                        icon: const HwIcon('chevron-left', size: 18),
                        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(l10n.donReviewTitle,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink0)),
                      ),
                      if (_zoom > 1)
                        IconButton(
                          icon: const HwIcon('fit', size: 18),
                          tooltip: l10n.donFitView,
                          onPressed: () => setState(() {
                            _zoom = 1;
                            _pan = Offset.zero;
                          }),
                        ),
                      if (s.corrections > 0)
                        HwButton(
                          label: l10n.donReset,
                          onPressed: () => _edit([...s.detected]),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    child: Text(s.parts.isEmpty ? l10n.donNoParts : l10n.donReviewHint,
                        style: TextStyle(fontSize: 13, color: p.ink2, height: 1.4)),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: p.paper0,
                        borderRadius: BorderRadius.circular(HwTheme.rLg),
                        border: Border.all(color: p.paper2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: LayoutBuilder(builder: (ctx, c) {
                        final fit = SampleFit(s, c.biggest, margin: 24, zoom: _zoom, pan: _pan);
                        return Listener(
                          onPointerSignal: (e) {
                            if (e is PointerScrollEvent) {
                              _zoomTo(_zoom * math.pow(0.998, e.scrollDelta.dy), e.localPosition);
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _tap(fit, d.localPosition),
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onScaleEnd: (_) => _onScaleEnd(fit),
                            child: CustomPaint(
                              size: c.biggest,
                              painter: SamplePainter(s, p, l10n, draft: _draft, zoom: _zoom, pan: _pan),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(children: [
                      HwButton(
                        label: l10n.donDiscard,
                        color: HwTheme.syncConflict,
                        onPressed: _discard,
                      ),
                      const Spacer(),
                      HwButton(
                        label: l10n.donMarkReviewed,
                        style: HwButtonStyle.primary,
                        onPressed: s.parts.isEmpty ? null : _markReviewed,
                      ),
                    ]),
                  ),
                ],
              ),
      ),
    );
  }
}
