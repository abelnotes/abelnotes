import 'package:flutter/painting.dart';

// Web stand-in for pen_input_channel.dart. The native bridges exist because
// desktop embedders drop pen pressure/sub-pixel data; the browser delivers
// both (Apple Pencil included) through ordinary pointer events, so these are
// all no-ops that report "no override available".

class PenInputChannel {
  static void register({
    required void Function(bool down) onBarrel,
    required void Function(bool down) onInverted,
    void Function(String phase, Offset position, double pressure)? onBarrelPen,
  }) {}

  static void unregister() {}
}

class WindowsPenSubpixel {
  static void update(Offset pos, bool contact) {}
  static Offset? latestFresh({int maxAgeMs = 40}) => null;
}

class LinuxPenPressure {
  static void register({VoidCallback? onProximityOut}) {}
  static double latest({int maxAgeMs = 120}) => -1;
  static double get tiltX => 0;
  static double get tiltY => 0;
  static void unregister() {}
}
