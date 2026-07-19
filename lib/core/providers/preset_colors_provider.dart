import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-customizable preset color palette shown in the toolbar.
///
/// - Tap a slot  → select that color as the active tool color (toolbar-side)
/// - Long-press a slot → swap out with a different color via the picker UI
/// - Move L / Move R → reorder slots without drag gestures (reliable on
///   iPad stylus where long-press + drag would conflict)
///
/// Persisted to SharedPreferences under the key [_prefsKey].
class PresetColorsNotifier extends StateNotifier<List<int>> {
  static const _prefsKey = 'toolbar_preset_colors_v1';
  static const defaults = <int>[
    0xFF000000, // black
    0xFF1565C0, // deep blue
    0xFFC62828, // red
    0xFFFFFFFF, // white
    0xFFFF9800, // orange
    0xFF2196F3, // light blue
  ];

  PresetColorsNotifier() : super(defaults) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<int>();
      if (list.length == defaults.length) state = list;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(state));
    } catch (_) {}
  }

  /// Replace slot [index] with a new color.
  void setColor(int index, int color) {
    if (index < 0 || index >= state.length) return;
    final next = List<int>.from(state);
    next[index] = color;
    state = next;
    _persist();
  }

  /// Swap two slot positions.
  void swap(int a, int b) {
    if (a < 0 || a >= state.length) return;
    if (b < 0 || b >= state.length) return;
    if (a == b) return;
    final next = List<int>.from(state);
    final tmp = next[a];
    next[a] = next[b];
    next[b] = tmp;
    state = next;
    _persist();
  }
}

final presetColorsProvider =
    StateNotifierProvider<PresetColorsNotifier, List<int>>((ref) {
  return PresetColorsNotifier();
});
