// One sample written to a prompt: the ink and what it shows (circuit parts or
// a formula), in the shape the receiver accepts (donate/src/schema.js in the
// site repo). See README.md.

import 'dart:math' as math;

/// The detector's classes, as the receiving schema lists them.
/// test/donation_sample_test.dart checks them against the bundled model.
const List<String> kDonationSymbols = [
  'resistor',
  'capacitor',
  'capacitor.polarized',
  'inductor',
  'diode',
  'voltage.dc',
  'voltage.ac',
  'voltage.battery',
  'current_source',
  'transistor.bjt',
  'transistor.fet',
  'opamp',
  'ic',
  'transformer',
  'switch',
  'gnd',
  'vss',
  'junction',
  'crossover',
  'terminal',
  'arrow',
  'text',
];

/// The receiver's limits (schema.js LIMITS).
const int kMaxStrokesPerSample = 2000;
const int kMaxPointsPerSample = 40000;
const int kMaxPartsPerSample = 500;
const int kMaxSampleMs = 3600000;
const int kMaxLatexChars = 1000;

enum DonationKind { circuit, formula }

/// Why a formula label cannot be sent as it is.
enum LatexProblem { empty, tooLong, notAscii }

/// The receiver takes printable ASCII only, up to [kMaxLatexChars].
LatexProblem? latexProblem(String latex) {
  if (latex.trim().isEmpty) return LatexProblem.empty;
  if (latex.length > kMaxLatexChars) return LatexProblem.tooLong;
  if (!RegExp(r'^[\x20-\x7e]+$').hasMatch(latex)) return LatexProblem.notAscii;
  return null;
}

class DonationPart {
  const DonationPart(this.symbol, this.x, this.y, this.w, this.h, {this.detected});

  final String symbol;
  final double x, y, w, h;

  /// The prompt's symbol; null for a part the reviewer added.
  final String? detected;

  bool contains(double px, double py) => px >= x && px <= x + w && py >= y && py <= y + h;

  DonationPart withSymbol(String s) => DonationPart(s, x, y, w, h, detected: detected);

  Map<String, Object?> toJson() => {
        'symbol': symbol,
        'box': [x, y, w, h],
        if (detected != null) 'detected': detected,
      };

  static DonationPart? fromJson(Object? j) {
    if (j is! Map) return null;
    final box = j['box'];
    final symbol = j['symbol'];
    if (symbol is! String || box is! List || box.length != 4 || box.any((v) => v is! num)) return null;
    final b = [for (final v in box) (v as num).toDouble()];
    final detected = j['detected'];
    return DonationPart(symbol, b[0], b[1], b[2], b[3], detected: detected is String ? detected : null);
  }

  /// What leaves the device: the final symbol and box, no detector guess.
  Map<String, Object> toWire() => {
        'symbol': symbol,
        'box': [_r1(x), _r1(y), math.max(0.1, _r1(w)), math.max(0.1, _r1(h))],
      };
}

class DonationSample {
  const DonationSample({
    required this.id,
    required this.created,
    required this.strokes,
    this.kind = DonationKind.circuit,
    this.parts = const [],
    this.detected = const [],
    this.latex = '',
    this.prompt,
    this.reviewed = false,
  });

  final String id;
  final DateTime created;

  /// Flat [x, y, t, p, ...] per stroke. Units: the pad is 512 wide
  /// (kPadUnits), origin at the ink's top-left; t in ms from the first
  /// point, p in 0..1.
  final List<List<double>> strokes;
  final DonationKind kind;

  /// Circuit: the parts as reviewed.
  final List<DonationPart> parts;

  /// Circuit: the part as prompted, for Reset.
  final List<DonationPart> detected;

  /// Formula: the LaTeX as reviewed.
  final String latex;

  /// Formula: the prompt's LaTeX, for Reset.
  final String? prompt;

  /// The writer confirmed it and the sample may be sent.
  final bool reviewed;

  bool get isFormula => kind == DonationKind.formula;

  /// Has a label the receiver accepts.
  bool get labelled => isFormula ? latexProblem(latex) == null : parts.isNotEmpty;

  /// Reviewed and labelled: goes with the next send.
  bool get sendable => reviewed && labelled;

  /// Drawing extent, in sample units.
  double get width => _extent(0);
  double get height => _extent(1);

  double _extent(int axis) {
    var m = 1.0;
    for (final s in strokes) {
      for (var i = axis; i < s.length; i += 4) {
        if (s[i] > m) m = s[i];
      }
    }
    for (final p in parts) {
      m = math.max(m, axis == 0 ? p.x + p.w : p.y + p.h);
    }
    return m;
  }

  /// Parts changed, added or removed against the prompt; for a formula,
  /// whether the LaTeX differs from it.
  int get corrections {
    if (isFormula) return prompt != null && prompt != latex ? 1 : 0;
    final kept = parts.where((p) => p.detected != null).length;
    return parts.where((p) => p.detected != p.symbol).length + (detected.length - kept);
  }

  DonationSample copyWith({List<DonationPart>? parts, String? latex, bool? reviewed}) => DonationSample(
        id: id,
        created: created,
        strokes: strokes,
        kind: kind,
        parts: parts ?? this.parts,
        detected: detected,
        latex: latex ?? this.latex,
        prompt: prompt,
        reviewed: reviewed ?? this.reviewed,
      );

  /// Written to a prompt: [strokes] already in sample units (flat, origin
  /// anywhere), [label] the prompt's LaTeX or circuit symbol. A circuit's
  /// part is the box around all of the ink. Counts as reviewed: the writer
  /// confirmed it by moving on. Null when empty or over the limits.
  static DonationSample? guided({
    required String id,
    required DateTime created,
    required DonationKind kind,
    required List<List<double>> strokes,
    required String label,
  }) {
    final kept = [for (final s in strokes) if (s.length >= 4 && s.length % 4 == 0) s];
    final points = kept.fold<int>(0, (n, s) => n + s.length ~/ 4);
    if (kept.isEmpty || kept.length > kMaxStrokesPerSample || points > kMaxPointsPerSample) return null;
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    var t0 = double.infinity;
    for (final s in kept) {
      for (var i = 0; i < s.length; i += 4) {
        minX = math.min(minX, s[i]);
        minY = math.min(minY, s[i + 1]);
        maxX = math.max(maxX, s[i]);
        maxY = math.max(maxY, s[i + 1]);
        t0 = math.min(t0, s[i + 2]);
      }
    }
    final out = [
      for (final s in kept)
        [
          for (var i = 0; i < s.length; i += 4) ...[
            _r1(s[i] - minX),
            _r1(s[i + 1] - minY),
            (s[i + 2] - t0).clamp(0, kMaxSampleMs).roundToDouble(),
            (s[i + 3].clamp(0.0, 1.0) * 100).roundToDouble() / 100,
          ]
        ]
    ];
    if (kind == DonationKind.formula) {
      if (latexProblem(label) != null) return null;
      return DonationSample(
          id: id,
          created: created,
          strokes: out,
          kind: kind,
          latex: label,
          prompt: label,
          reviewed: true);
    }
    if (!kDonationSymbols.contains(label)) return null;
    // A dot still gets a box the receiver accepts.
    final part = DonationPart(label, 0, 0, math.max(1, _r1(maxX - minX)), math.max(1, _r1(maxY - minY)),
        detected: label);
    return DonationSample(
        id: id,
        created: created,
        strokes: out,
        parts: [part],
        detected: [part],
        reviewed: true);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'created': created.toUtc().toIso8601String(),
        'kind': kind.name,
        'reviewed': reviewed,
        'strokes': strokes,
        if (!isFormula) 'parts': [for (final p in parts) p.toJson()],
        if (!isFormula) 'detected': [for (final p in detected) p.toJson()],
        if (isFormula) 'latex': latex,
        if (prompt != null) 'prompt': prompt,
      };

  /// Reads [toJson].
  static DonationSample? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], created = DateTime.tryParse('${j['created']}');
    final strokes = j['strokes'];
    if (id is! String || created == null || strokes is! List) return null;
    final flat = <List<double>>[];
    for (final s in strokes) {
      if (s is! List || s.isEmpty || s.length % 4 != 0 || s.any((v) => v is! num)) return null;
      flat.add([for (final v in s) (v as num).toDouble()]);
    }
    final kind = DonationKind.values.asNameMap()[j['kind']];
    if (kind == null) return null;
    List<DonationPart> partsOf(Object? list) =>
        (list is List ? list : const []).map(DonationPart.fromJson).whereType<DonationPart>().toList();
    final latex = j['latex'], prompt = j['prompt'];
    return DonationSample(
      id: id,
      created: created,
      strokes: flat,
      kind: kind,
      parts: partsOf(j['parts']),
      detected: partsOf(j['detected']),
      latex: latex is String ? latex : '',
      prompt: prompt is String ? prompt : null,
      reviewed: j['reviewed'] == true,
    );
  }

  /// The sample as sent: strokes and the final label only.
  Map<String, Object> toWire() => {
        'kind': kind.name,
        'source': 'guided',
        'strokes': strokes,
        'label': isFormula
            ? {'latex': latex}
            : {
                'parts': [for (final p in parts) p.toWire()],
              },
      };
}

double _r1(double v) => (v * 10).roundToDouble() / 10;
