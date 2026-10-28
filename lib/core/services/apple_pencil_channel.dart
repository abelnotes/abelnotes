import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apple Pencil double-tap (2nd generation, Pro) in the iPad app.
///
/// Flutter has no API for it: the runner (`ios/Runner/AppDelegate.swift`,
/// `PencilDoubleTap`) puts a `UIPencilInteraction` on the Flutter view and
/// reports each tap together with the user's system preference
/// (Settings → Apple Pencil): `switchEraser`, `switchPrevious`, `ignore`,
/// or `other` for actions the app has no counterpart for (colour palette).
///
/// No-op everywhere else, the web included: Safari never passes the
/// double-tap to a page.
class ApplePencilChannel {
  static const MethodChannel _channel = MethodChannel('abelnotes/pencil');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static void register(void Function(String action) onDoubleTap) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'doubleTap') return;
      final action = (call.arguments as Map?)?['action'] as String?;
      if (action != null) onDoubleTap(action);
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
