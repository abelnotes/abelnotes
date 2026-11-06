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

  static void Function(String action)? _current;

  static void register(void Function(String action) onDoubleTap) {
    if (!_supported) return;
    _current = onDoubleTap;
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

  /// Only the canvas that registered last can clear the handler, so one
  /// being disposed after its replacement opened doesn't silence it.
  static void unregister(void Function(String action) onDoubleTap) {
    if (!_supported || _current != onDoubleTap) return;
    _current = null;
    _channel.setMethodCallHandler(null);
  }
}
