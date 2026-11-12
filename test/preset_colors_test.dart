import 'package:abelnotes/core/providers/preset_colors_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const d = PresetColorsNotifier.defaults;

  test('two full rows of defaults', () {
    expect(d.length, PresetColorsNotifier.perRow * 2);
    expect(d.toSet().length, d.length);
  });

  test('a palette saved with one row keeps its colors and gains the second',
      () {
    final saved = [1, 2, 3, 4, 5, 6];
    final out = PresetColorsNotifier.withDefaults(saved);
    expect(out.sublist(0, 6), saved);
    expect(out.sublist(6), d.sublist(6));
  });

  test('a full palette is kept as saved', () {
    final saved = List.generate(d.length, (i) => 100 + i);
    expect(PresetColorsNotifier.withDefaults(saved), saved);
  });

  test('extra saved slots are dropped', () {
    final saved = List.generate(d.length + 3, (i) => i);
    expect(PresetColorsNotifier.withDefaults(saved).length, d.length);
  });
}
