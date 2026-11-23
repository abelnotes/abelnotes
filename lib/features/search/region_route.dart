import 'dart:math' as math;

/// What a group of strokes is, as the region router sees it.
enum RegionKind { text, formula, circuit, drawing }

/// The bundled router model (assets/models/region_router.abnn).
const regionRouterAsset = 'assets/models/region_router.abnn';

/// Part of the search stamp: a new router re-reads every page.
const regionRouterVersion = 'r2s0-20261121';

/// Search sends a handwritten line to OCR only when p(text) is at least this
/// (on a labelled bench this keeps ~98% of text and drops ~80% of formulas).
const ocrTextThreshold = 0.2;

/// The router's class probabilities for one stroke group.
class RegionProbs {
  final double text, formula, circuit, drawing;
  const RegionProbs(this.text, this.formula, this.circuit, this.drawing);

  /// Softmax of the model's logits (text, formula, circuit, drawing).
  factory RegionProbs.fromLogits(List<double> l) {
    final m = l.reduce(math.max);
    final e = [for (final v in l) math.exp(v - m)];
    final s = e.fold<double>(0, (a, b) => a + b);
    return RegionProbs(e[0] / s, e[1] / s, e[2] / s, e[3] / s);
  }

  double of(RegionKind k) => switch (k) {
        RegionKind.text => text,
        RegionKind.formula => formula,
        RegionKind.circuit => circuit,
        RegionKind.drawing => drawing,
      };

  /// Classes from most to least likely.
  List<RegionKind> get ranked =>
      [...RegionKind.values]..sort((a, b) => of(b).compareTo(of(a)));

  RegionKind get top => ranked.first;

  @override
  String toString() => 'RegionProbs(text ${text.toStringAsFixed(3)}, formula '
      '${formula.toStringAsFixed(3)}, circuit ${circuit.toStringAsFixed(3)}, drawing '
      '${drawing.toStringAsFixed(3)})';
}
