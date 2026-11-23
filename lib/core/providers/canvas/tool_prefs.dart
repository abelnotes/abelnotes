import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';

/// Per-tool memory of (strokeWidth, color, opacity, eraserSize), restored
/// when the user re-enters a tool, plus its debounced persist and the startup pen.
class ToolPrefs {
  ToolPrefs(this._core) {
    loaded = _load();
  }

  final CanvasCore _core;
  final Map<CanvasTool, ToolSettings> _prefs = {};
  Timer? _persistDebounce;

  /// Completes once the saved prefs are read.
  late final Future<void> loaded;

  /// Last eraser sub-mode the user explicitly picked.
  CanvasTool lastEraserMode = CanvasTool.eraserStroke;

  /// Tools with user-tunable settings; lasso/text/image/pan/laser/shape have none.
  static bool hasSettings(CanvasTool t) {
    return t == CanvasTool.pen ||
        t == CanvasTool.ballpoint ||
        t == CanvasTool.brush ||
        t == CanvasTool.calligraphy ||
        t == CanvasTool.highlighter ||
        t == CanvasTool.eraserStandard ||
        t == CanvasTool.eraserStroke;
  }

  /// Remembers the outgoing tool's settings when [from] carries any.
  void rememberOutgoing(CanvasTool from, ToolSettings settings) {
    if (hasSettings(from)) _prefs[from] = settings;
  }

  /// Settings for [tool] on entering it, given the [current] ones.
  ToolSettings settingsFor(CanvasTool tool, ToolSettings current) {
    final remembered = _prefs[tool];
    if (remembered != null) return remembered;
    if (tool == CanvasTool.highlighter) {
      return current.copyWith(
        color: 0xFFFFEB3B,
        strokeWidth: 12.0,
        opacity: 0.35,
      );
    }
    if (hasSettings(tool)) {
      // First visit to a pen-class tool: default width, full opacity, keep
      // the colour unless it came from the highlighter default.
      return current.copyWith(
        strokeWidth: AppConfig.defaultStrokeWidth,
        opacity: 1.0,
        color: current.color == 0xFFFFEB3B ? 0xFF000000 : current.color,
      );
    }
    return current;
  }

  /// Snapshot the active tool's settings into the memory and schedule a persist.
  void rememberCurrent() {
    final s = _core.state;
    if (s == null) return;
    if (!hasSettings(s.currentTool)) return;
    _prefs[s.currentTool] = s.toolSettings;
    persist();
  }

  /// Debounced write of the prefs blob, once the slider gesture settles.
  void persist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 600), _write);
  }

  /// Writes pending prefs now and drops the timer, so nothing outlives the notifier.
  void dispose() {
    if (!(_persistDebounce?.isActive ?? false)) return;
    _persistDebounce!.cancel();
    unawaited(_write());
  }

  Future<void> _write() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blob = <String, dynamic>{
        'lastEraserMode': lastEraserMode.name,
        'tools': {
          for (final e in _prefs.entries)
            e.key.name: {
              'color': e.value.color,
              'strokeWidth': e.value.strokeWidth,
              'opacity': e.value.opacity,
              'eraserSize': e.value.eraserSize.name,
              if (e.value.eraserDiameterPt != null)
                'eraserDiameterPt': e.value.eraserDiameterPt,
            },
        },
      };
      await prefs.setString('canvas_tool_prefs_v1', jsonEncode(blob));
    } catch (_) {/* non-critical */}
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('canvas_tool_prefs_v1');
      if (raw == null || raw.isEmpty) return;
      final blob = jsonDecode(raw) as Map<String, dynamic>;
      final lastEr = blob['lastEraserMode'] as String?;
      if (lastEr != null) {
        lastEraserMode = CanvasTool.values.firstWhere(
          (t) => t.name == lastEr,
          orElse: () => CanvasTool.eraserStroke,
        );
      }
      final tools = blob['tools'] as Map<String, dynamic>?;
      if (tools != null) {
        tools.forEach((toolName, settings) {
          final tool = CanvasTool.values.firstWhere(
            (t) => t.name == toolName,
            orElse: () => CanvasTool.pen,
          );
          final s = settings as Map<String, dynamic>;
          _prefs[tool] = ToolSettings(
            color: s['color'] as int? ?? 0xFF000000,
            strokeWidth: (s['strokeWidth'] as num?)?.toDouble() ??
                AppConfig.defaultStrokeWidth,
            opacity: (s['opacity'] as num?)?.toDouble() ?? 1.0,
            eraserSize: EraserSize.values.firstWhere(
              (e) => e.name == (s['eraserSize'] as String?),
              orElse: () => EraserSize.medium,
            ),
            eraserDiameterPt: (s['eraserDiameterPt'] as num?)?.toDouble(),
          );
        });
      }
    } catch (_) {/* non-critical */}
  }

  /// Pen a freshly opened notebook starts with: the first saved pen preset,
  /// else the pen as last left, else the defaults.
  ToolSettings startupPen() {
    final remembered = _prefs[CanvasTool.pen] ?? const ToolSettings();
    for (final p
        in _core.ref.read(appSettingsProvider).presetsFor(CanvasTool.pen)) {
      if (p != null) {
        return remembered.copyWith(
          color: p.color,
          strokeWidth: p.strokeWidth,
          opacity: p.opacity,
        );
      }
    }
    return remembered;
  }
}
