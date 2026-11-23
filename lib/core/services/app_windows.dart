import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:abelnotes/core/platform/io.dart';

/// The app's other windows (Android runs one Flutter engine per window).
/// Answers as if this were the only window wherever there is no such
/// platform side, so single-window platforms behave as before.
class AppWindows {
  static const _channel = MethodChannel('abelnotes/windows');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<T?> _call<T>(String method, [Object? arg]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, arg);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Marks [notebookId] as open here; false when another window has it.
  static Future<bool> claim(String notebookId) async =>
      await _call<bool>('claim', notebookId) ?? true;

  static Future<void> release(String notebookId) =>
      _call<void>('release', notebookId);

  static Future<bool> heldElsewhere(String notebookId) async =>
      await _call<bool>('heldElsewhere', notebookId) ?? false;

  /// Only one window runs the library's background sync.
  static Future<bool> isLeader() async => await _call<bool>('isLeader') ?? true;

  static Future<void> openInNewWindow(String notebookId) =>
      _call<bool>('openInNewWindow', notebookId);

  static final _saved = StreamController<String>.broadcast();
  static bool _listening = false;

  /// Notebooks another window just saved to disk.
  static Stream<String> get saved {
    if (supported && !_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'saved' && call.arguments is String) {
          _saved.add(call.arguments as String);
        }
      });
    }
    return _saved.stream;
  }

  /// Tells the other windows [notebookId] changed on disk.
  static Future<void> notifySaved(String notebookId) =>
      _call<void>('notifySaved', notebookId);

  /// The notebook this window was opened for, once.
  static Future<String?> takeLaunchNotebook() =>
      _call<String>('takeLaunchNotebook');
}

/// A notebook that another window of the app has open.
class NotebookOpenElsewhereException implements Exception {
  @override
  String toString() =>
      'NotebookOpenElsewhereException: notebook is open in another window';
}
