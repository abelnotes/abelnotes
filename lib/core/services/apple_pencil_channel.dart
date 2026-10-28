import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apple Pencil double-tap (2nd generation, Pro) and squeeze (Pro) in the
/// iPad app.
///
/// Flutter has no API for either: the runner (`ios/Runner/AppDelegate.swift`,
/// `PencilGestures`) puts a `UIPencilInteraction` on the Flutter view and
/// reports each gesture together with what the user picked for it in
/// Settings → Apple Pencil: `switchEraser`, `switchPrevious`,
/// `showColorPalette`, `showInkAttributes`, `showContextualPalette`,
/// `runSystemShortcut` (the system already ran it), `ignore` or `other`.
/// Where the Pencil hovers comes along when iPadOS knows it (17.5+), in
/// global logical pixels.
///
/// No-op everywhere else, the web included: Safari never passes these
/// gestures to a page.
class ApplePencilChannel {
  static const MethodChannel _channel = MethodChannel('abelnotes/pencil');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static void register({
    required void Function(String action, Offset? at) onDoubleTap,
    required void Function(String action, Offset? at) onSqueeze,
  }) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<Object?, Object?>();
      final action = args?['action'] as String?;
      if (action == null) return;
      final x = (args!['x'] as num?)?.toDouble();
      final y = (args['y'] as num?)?.toDouble();
      final at = x != null && y != null ? Offset(x, y) : null;
      switch (call.method) {
        case 'doubleTap':
          onDoubleTap(action, at);
          break;
        case 'squeeze':
          onSqueeze(action, at);
          break;
      }
    });
    _attach();
  }

  static Future<void> _attach() async {
    try {
      await _channel.invokeMethod<void>('attach');
    } on MissingPluginException {
      // Runner without the bridge (tests, older builds).
    }
  }

  static void unregister() {
    if (!_supported) return;
    _channel.setMethodCallHandler(null);
  }
}
