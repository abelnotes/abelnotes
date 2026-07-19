import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// OS-level window control for desktop, backed by our own runner code
/// instead of a plugin.
///
/// History: presentation mode first used the `window_manager` package for
/// fullscreen, but its Linux side hooks GTK window signals and raced the
/// embedder during window teardown — closing the app crashed with
/// "invalid unclassed pointer in cast to 'FlView'" GTK criticals. The
/// replacement is a ~20-line method channel in `linux/runner/
/// my_application.cc` (same infrastructure the pen-pressure bridge already
/// uses) calling plain `gtk_window_fullscreen()` — nothing new is attached
/// to the window lifecycle, so quitting while fullscreen can't race.
///
/// Windows/macOS: currently a silent no-op — presentation mode there hides
/// the in-app chrome only. Wire the equivalent runner-side call when those
/// desktops become a launch target.
class DesktopWindow {
  static const MethodChannel _channel = MethodChannel('handwriter/window');

  static bool get _isLinuxDesktop => !kIsWeb && Platform.isLinux;

  static Future<void> setFullScreen(bool enabled) async {
    if (!_isLinuxDesktop) return;
    try {
      await _channel.invokeMethod('setFullScreen', enabled);
    } on MissingPluginException {
      // Older runner build without the channel — degrade to chrome-only.
    }
  }
}
