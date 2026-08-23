import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the armed tool survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Nothing picked yet: the editor falls back to pan on phones.
    expect(c.read(appSettingsProvider).lastTool, isNull);

    c.read(appSettingsProvider.notifier).setLastTool('highlighter');
    expect(c.read(appSettingsProvider).lastTool, 'highlighter');

    // Persisted, so the next launch reopens with the same tool.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('app_settings_v1')!) as Map<String, dynamic>;
    expect(stored['last_tool'], 'highlighter');

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    // The notifier loads its prefs asynchronously in its constructor.
    restarted.read(appSettingsProvider);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
      if (restarted.read(appSettingsProvider).lastTool != null) break;
    }
    expect(restarted.read(appSettingsProvider).lastTool, 'highlighter');
  });

  test('stylus-only is off unless the user asks for it', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Null means "finger draws"; the editor reads it as false on every
    // platform now, phones included.
    expect(c.read(appSettingsProvider).stylusOnlyDrawing, isNull);

    c.read(appSettingsProvider.notifier).setStylusOnlyDrawing(true);
    expect(c.read(appSettingsProvider).stylusOnlyDrawing, isTrue);
  });
}
