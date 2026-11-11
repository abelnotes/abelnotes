import 'dart:convert';

import 'package:abelnotes/core/providers/preset_colors_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a saved 6-color palette keeps its colors and gains the new row',
      () async {
    final old = [1, 2, 3, 4, 5, 6];
    SharedPreferences.setMockInitialValues(
        {'toolbar_preset_colors_v1': jsonEncode(old)});
    final n = PresetColorsNotifier();
    await Future<void>.delayed(Duration.zero);
    expect(n.state.length, PresetColorsNotifier.defaults.length);
    expect(n.state.take(6), old);
    expect(n.state.skip(6), PresetColorsNotifier.defaults.skip(6));
  });
}
