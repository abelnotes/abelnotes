import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';

const _key = 'app_settings_v1';

Future<AppSettingsNotifier> _boot([Map<String, dynamic>? stored]) async {
  SharedPreferences.setMockInitialValues(
      stored == null ? {} : {_key: jsonEncode(stored)});
  final n = AppSettingsNotifier();
  await n.ready;
  return n;
}

void main() {
  test('side buttons default to lasso (lower) and eraser (upper)', () async {
    final n = await _boot();
    expect(n.state.penLowerButton, PenButtonAction.lasso);
    expect(n.state.penUpperButton, PenButtonAction.eraser);
  });

  test('a picked action survives a restart', () async {
    final n = await _boot();
    n.setPenButton(upper: false, action: PenButtonAction.eraser);
    n.setPenButton(upper: true, action: PenButtonAction.none);
    await Future<void>.delayed(Duration.zero);
    final again = AppSettingsNotifier();
    await again.ready;
    expect(again.state.penLowerButton, PenButtonAction.eraser);
    expect(again.state.penUpperButton, PenButtonAction.none);
  });

  test('an unknown stored value falls back to the default', () async {
    final n = await _boot({'pen_button_lower': 'laser'});
    expect(n.state.penLowerButton, PenButtonAction.lasso);
  });
}
