// ═══════════════════════════════════════════════════════════════
//  pen_monitor_service.dart
//
//  Linux-only: maps a graphics-tablet / stylus to a single monitor by
//  applying an xinput "Coordinate Transformation Matrix", so the pen's
//  active area covers exactly one screen instead of being stretched
//  across the whole multi-monitor desktop.
//
//  This is the in-app port of the standalone `pennina.sh` script: same
//  xrandr geometry parsing + matrix math, but driven from the editor UI
//  with a monitor picker (no terminal needed) and reversible from the
//  same menu.
// ═══════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math' as math;

/// A connected, positioned monitor as reported by `xrandr --query`.
class PenMonitorInfo {
  final String name;
  final int x;
  final int y;
  final int width;
  final int height;

  const PenMonitorInfo({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  String get geometry => '$width×$height @ ($x, $y)';
}

class PenMonitorException implements Exception {
  final String message;
  PenMonitorException(this.message);
  @override
  String toString() => message;
}

class PenMonitorService {
  /// Pen-to-monitor mapping relies on X11 tooling (xrandr / xinput); only
  /// offer it on Linux. On Wayland these commands simply fail and the UI
  /// surfaces the error.
  static bool get isSupported => Platform.isLinux;

  // e.g. "HDMI-1 connected primary 1920x1080+0+0 (normal ...) 509mm x 286mm"
  //      "DP-2 connected 2560x1440+1920+0 ..."
  static final RegExp _connectedLine =
      RegExp(r'^(\S+) connected.*?(\d+)x(\d+)\+(-?\d+)\+(-?\d+)');

  // Stylus / pen / wacom device, matched against `xinput list --name-only`.
  static final RegExp _penName =
      RegExp(r'stylus|pen|wacom', caseSensitive: false);

  /// Active monitors (connected + positioned). Throws [PenMonitorException]
  /// if xrandr is missing or returns nothing usable.
  Future<List<PenMonitorInfo>> listMonitors() async {
    final ProcessResult res;
    try {
      res = await Process.run('xrandr', const ['--query']);
    } on ProcessException catch (e) {
      throw PenMonitorException('xrandr non trovato: ${e.message}');
    }
    if (res.exitCode != 0) {
      throw PenMonitorException('xrandr ha fallito: ${res.stderr}');
    }
    final out = '${res.stdout}';
    final monitors = <PenMonitorInfo>[];
    for (final line in out.split('\n')) {
      final m = _connectedLine.firstMatch(line);
      if (m == null) continue;
      monitors.add(PenMonitorInfo(
        name: m.group(1)!,
        width: int.parse(m.group(2)!),
        height: int.parse(m.group(3)!),
        x: int.parse(m.group(4)!),
        y: int.parse(m.group(5)!),
      ));
    }
    if (monitors.isEmpty) {
      throw PenMonitorException('Nessun monitor attivo rilevato.');
    }
    return monitors;
  }

  /// Name of the first stylus/pen/wacom device, or null if none is found.
  Future<String?> findPenDevice() async {
    final ProcessResult res;
    try {
      res = await Process.run('xinput', const ['list', '--name-only']);
    } on ProcessException catch (e) {
      throw PenMonitorException('xinput non trovato: ${e.message}');
    }
    if (res.exitCode != 0) return null;
    for (final line in '${res.stdout}'.split('\n')) {
      final name = line.trim();
      if (name.isNotEmpty && _penName.hasMatch(name)) return name;
    }
    return null;
  }

  /// Constrain the pen to [monitor]. [allMonitors] is the full set returned
  /// by [listMonitors] (needed to size the transform against the whole
  /// desktop). Mirrors the matrix pennina.sh builds:
  ///
  ///   [ w/W   0    x/W ]
  ///   [  0   h/H   y/H ]
  ///   [  0    0     1  ]
  ///
  /// where (w,h,x,y) is the monitor and (W,H) the total desktop extent.
  Future<void> mapPenToMonitor(
    PenMonitorInfo monitor,
    List<PenMonitorInfo> allMonitors,
  ) async {
    final pen = await findPenDevice();
    if (pen == null) {
      throw PenMonitorException(
          'Nessun dispositivo penna trovato (stylus/pen/wacom).');
    }

    var totalW = 0;
    var totalH = 0;
    for (final m in allMonitors) {
      totalW = math.max(totalW, m.x + m.width);
      totalH = math.max(totalH, m.y + m.height);
    }
    if (totalW <= 0 || totalH <= 0) {
      throw PenMonitorException('Geometria desktop non valida.');
    }

    final matrix = <double>[
      monitor.width / totalW, 0, monitor.x / totalW, //
      0, monitor.height / totalH, monitor.y / totalH, //
      0, 0, 1,
    ].map((v) => v.toStringAsFixed(6)).toList();

    await _setMatrix(pen, matrix);
  }

  /// Reset the pen to span the entire desktop again (identity matrix).
  Future<void> resetPen() async {
    final pen = await findPenDevice();
    if (pen == null) {
      throw PenMonitorException('Nessun dispositivo penna trovato.');
    }
    await _setMatrix(
        pen, const ['1', '0', '0', '0', '1', '0', '0', '0', '1']);
  }

  Future<void> _setMatrix(String pen, List<String> matrix) async {
    final ProcessResult res;
    try {
      res = await Process.run('xinput', [
        'set-prop',
        pen,
        'Coordinate Transformation Matrix',
        ...matrix,
      ]);
    } on ProcessException catch (e) {
      throw PenMonitorException('xinput non trovato: ${e.message}');
    }
    if (res.exitCode != 0) {
      throw PenMonitorException('xinput set-prop ha fallito: ${res.stderr}');
    }
  }
}
