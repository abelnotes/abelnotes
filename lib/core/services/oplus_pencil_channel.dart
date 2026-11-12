import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:abelnotes/core/services/crash_logger.dart';

/// Actions exposed by the tablet's system pen settings. Unknown/off is a no-op.
String? oplusPencilActionForMode(int mode) => switch (mode) {
      1 => 'switchEraser',
      2 => 'switchPrevious',
      3 => 'showColorPalette',
      _ => null,
    };

/// Android-only bridge for OPPO / OnePlus system pen gestures.
/// Only the current registered editor owns the callback.
class OplusPencilChannel {
  static const _channel = MethodChannel('abelnotes/oplus_pencil');
  static void Function(int)? _owner;
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void register(void Function(int) callback) {
    if (!_supported) return;
    _owner = callback;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'doubleTap') return;
      final args = call.arguments;
      final mode = args is Map ? args['mode'] : null;
      if (mode is! int) return;
      unawaited(CrashLogger.append(
          '[OplusPencil] double-tap received; systemMode=$mode'));
      _owner?.call(mode);
    });
    _attach(callback);
  }

  static Future<void> _attach(void Function(int) callback) async {
    try {
      final status = await _channel.invokeMethod<Object?>('attach');
      if (_owner == callback) {
        await CrashLogger.append('[OplusPencil] bridge status: $status');
      }
    } on MissingPluginException {
      await CrashLogger.append(
          '[OplusPencil] native bridge unavailable in this build');
    } on PlatformException catch (e) {
      await CrashLogger.append('[OplusPencil] attach failed: ${e.code}');
    }
  }

  static void unregister(void Function(int) callback) {
    if (!_supported || _owner != callback) return;
    _owner = null;
    _channel.setMethodCallHandler(null);
    _detach();
  }

  static Future<void> _detach() async {
    try {
      await _channel.invokeMethod<void>('detach');
    } on MissingPluginException {
      // Older runners / tests have no bridge.
    } on PlatformException catch (e) {
      await CrashLogger.append('[OplusPencil] detach failed: ${e.code}');
    }
  }
}
