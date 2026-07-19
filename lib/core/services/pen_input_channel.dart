import 'dart:ffi';
import 'dart:io' show File, Platform, RandomAccessFile;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:abelnotes/core/services/crash_logger.dart';

/// Native pen-button bridge for the Windows runner.
///
/// Background: Flutter on Windows reads pen events via the legacy
/// mouse path, which strips `POINTER_PEN_INFO.penFlags`. Tablet
/// drivers (Gaomon / Huion / Wacom) expose the barrel side buttons
/// through those flags — but to Flutter the press arrives as a
/// generic `kind=mouse buttons=0x4`, indistinguishable from a real
/// middle-click. The C++ runner subscribes to WM_POINTER* in
/// parallel with Flutter, reads `penFlags`, and forwards transitions
/// over this channel.
///
/// Two logical buttons:
///   - `barrel`   → lower side button (`PEN_FLAG_BARREL`)
///   - `inverted` → upper side button or actual eraser end
///     (`PEN_FLAG_INVERTED`). Most Huion-class tablets report the
///     upper button this way.
///
/// No-op on non-Windows platforms (Apple Pencil / Android stylus
/// already arrive with full pressure + buttons via Flutter's normal
/// pointer pipeline).
class PenInputChannel {
  static const MethodChannel _channel = MethodChannel('handwriter/pen_input');

  static bool _registered = false;

  /// Hook callbacks for barrel-button state transitions and the
  /// barrel-driven pen gesture. Idempotent — calling twice with new
  /// callbacks replaces the previous ones.
  ///
  /// [onBarrelPen] receives `phase` ("down" / "move" / "up"),
  /// `position` in Flutter logical pixels (renderer-local — convert
  /// with `RenderBox.globalToLocal` before feeding the canvas), and
  /// normalised `pressure` in `[0, 1]`. Fires only while a side button
  /// is held — needed because Gaomon driverless suppresses Flutter's
  /// regular PointerEvents while the barrel is pressed.
  static void register({
    required void Function(bool down) onBarrel,
    required void Function(bool down) onInverted,
    void Function(String phase, Offset position, double pressure)? onBarrelPen,
  }) {
    if (kIsWeb || !Platform.isWindows) return;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<Object?, Object?>();
      if (args == null) return;
      switch (call.method) {
        case 'onBarrelChange':
          final button = args['button'] as String?;
          final down = args['down'] as bool? ?? false;
          switch (button) {
            case 'barrel':
              onBarrel(down);
              break;
            case 'inverted':
              onInverted(down);
              break;
          }
          break;
        case 'onBarrelPen':
          if (onBarrelPen == null) return;
          final phase = args['phase'] as String?;
          final x = (args['x'] as num?)?.toDouble();
          final y = (args['y'] as num?)?.toDouble();
          final pressure = (args['pressure'] as num?)?.toDouble() ?? 0.5;
          if (phase == null || x == null || y == null) return;
          onBarrelPen(phase, Offset(x, y), pressure);
          break;
        case 'onPenPos':
          final x = (args['x'] as num?)?.toDouble();
          final y = (args['y'] as num?)?.toDouble();
          final contact = args['contact'] as bool? ?? false;
          if (x == null || y == null) return;
          WindowsPenSubpixel.update(Offset(x, y), contact);
          break;
      }
    });
    _registered = true;
  }

  /// Clear the handler. Safe to call even if [register] was never
  /// invoked.
  static void unregister() {
    if (!_registered) return;
    _channel.setMethodCallHandler(null);
    _registered = false;
  }
}

/// Windows sub-pixel pen position cache.
///
/// Flutter's Windows embedder reads pointer positions from
/// `ptPixelLocation` — INTEGER client pixels — so the digitizer's
/// sub-pixel precision never reaches Dart. Zoomed out, that ±0.5 px
/// staircase spans 1-2 page units (≈ the stroke width) and the
/// renderer's Catmull-Rom turns it into a visible wave. The C++ runner
/// maps `ptHimetricLocation` through GetPointerDeviceRects to float
/// screen pixels and streams every sample here ("onPenPos", handled in
/// [PenInputChannel]); the canvas substitutes the fresh sample for the
/// quantized event position while drawing.
///
/// The C++ subclass runs BEFORE the engine's wndproc for the same
/// WM_POINTER message, so on arrival of a stylus PointerEvent the
/// matching sub-pixel sample is already cached.
class WindowsPenSubpixel {
  static Offset? _pos;
  static bool _contact = false;
  static int _atMs = 0;

  static void update(Offset pos, bool contact) {
    _pos = pos;
    _contact = contact;
    _atMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// The latest in-contact sample, in Flutter logical coordinates of the
  /// renderer window ("global" space), or null when stale (> [maxAgeMs]
  /// old — the pen stream pauses when the pen rests or leaves) or when
  /// the tip isn't touching.
  static Offset? latestFresh({int maxAgeMs = 40}) {
    if (_pos == null || !_contact) return null;
    final age = DateTime.now().millisecondsSinceEpoch - _atMs;
    return age <= maxAgeMs ? _pos : null;
  }
}

/// Linux pen-pressure bridge.
///
/// Flutter's Linux GTK embedder never reads the stylus axes, so
/// `PointerEvent.pressure` is always 0 on Linux (flutter/flutter#63209).
/// The native runner (`linux/runner/my_application.cc`) observes GDK motion
/// events, pulls `GDK_AXIS_PRESSURE`/tilt, and streams them here. We cache
/// the most recent sample; the canvas pointer handlers read [latest] to
/// override the missing pressure on the matching PointerMove.
///
/// No-op on non-Linux platforms (their normal pointer pipeline already
/// carries pressure).
class LinuxPenPressure {
  static const MethodChannel _channel =
      MethodChannel('handwriter/pen_input_linux');

  static bool _registered = false;
  static double _pressure = -1; // -1 = no real pressure available
  static double _tiltX = 0;
  static double _tiltY = 0;
  // Diagnostic latch: logged once when the first real pressure sample arrives
  // from the display-server path (runner `penSample`). Confirms pressure works
  // without any /dev/input access — the whole point of that path.
  static bool _serverPressureLogged = false;

  // ── evdev pressure source ───────────────────────────────────────
  // GtkGestureStylus (the native bridge above) does NOT fire for many
  // Gaomon/Huion/XP-Pen tablets on X11 — GDK classifies them as a
  // generic pointer, so no penSample ever arrives. The kernel still
  // exposes the real pen pressure on the ABS_PRESSURE axis of the
  // tablet's /dev/input/eventN node, readable directly and immune to
  // toolkit/grab quirks (same approach the sibling PhotoJ app uses).
  // We stream it here and feed the same [_pressure] cache the consumer
  // (canvas pointer handlers) already read via [latest].
  static RandomAccessFile? _evdevRaf;
  static bool _evdevRunning = false;
  // Pressure full-scale. Read from the kernel (EVIOCGABS) at startup so it's
  // exact for whatever tablet is attached; the literal here is only a fallback
  // if that ioctl fails, and it still auto-bumps up if a larger raw value
  // ever appears. NOT a per-device assumption.
  static double _evdevPmax = 2047;
  static List<int> _evdevLeftover = const [];

  static void register() {
    if (kIsWeb || !Platform.isLinux || _registered) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'penSample') return;
      final a = (call.arguments as Map?)?.cast<Object?, Object?>();
      if (a == null) return;
      final p = (a['pressure'] as num?)?.toDouble() ?? -1;
      if (p >= 0 && !_serverPressureLogged) {
        _serverPressureLogged = true;
        CrashLogger.append(
            '[Pen] pressure via display server (GDK axis) — no evdev needed');
      }
      _pressure = p;
      _tiltX = (a['tiltX'] as num?)?.toDouble() ?? 0;
      _tiltY = (a['tiltY'] as num?)?.toDouble() ?? 0;
    });
    _registered = true;
    _startEvdev();
  }

  /// Locate the tablet's /dev/input/eventN node by scanning
  /// /proc/bus/input/devices for a device whose ABS bitmask has the
  /// ABS_PRESSURE bit (24) set, preferring pen/stylus/tablet names. No
  /// hardcoded device id — works across Gaomon/Huion/Wacom/XP-Pen.
  static String? _detectPenEvdev() {
    try {
      final txt = File('/proc/bus/input/devices').readAsStringSync();
      final cands = <({String name, String ev})>[];
      for (final block in txt.split('\n\n')) {
        String name = '';
        String? ev;
        List<String>? absb;
        for (final line in block.split('\n')) {
          if (line.startsWith('N: Name=')) {
            name = line.substring(8).trim().replaceAll('"', '');
          } else if (line.startsWith('H: Handlers=')) {
            final m = RegExp(r'(event\d+)').firstMatch(line);
            if (m != null) ev = m.group(1);
          } else if (line.startsWith('B: ABS=')) {
            absb = line.substring(7).trim().split(RegExp(r'\s+'));
          }
        }
        if (ev == null || absb == null || absb.isEmpty) continue;
        final lastWord = int.tryParse(absb.last, radix: 16);
        if (lastWord == null) continue;
        if ((lastWord & (1 << 24)) != 0) cands.add((name: name, ev: ev));
      }
      if (cands.isEmpty) return null;
      cands.sort((a, b) {
        bool isPen(String n) =>
            RegExp(r'pen|stylus|tablet', caseSensitive: false).hasMatch(n);
        return (isPen(a.name) ? 0 : 1).compareTo(isPen(b.name) ? 0 : 1);
      });
      return '/dev/input/${cands.first.ev}';
    } catch (_) {
      return null;
    }
  }

  /// Stream ABS_PRESSURE from the pen's evdev node into [_pressure].
  static void _startEvdev() {
    if (kIsWeb || !Platform.isLinux || _evdevRunning) return;
    final path = _detectPenEvdev();
    if (path == null) {
      CrashLogger.append('[Pen] no ABS_PRESSURE tablet found');
      return;
    }
    // Ask the kernel for this device's real pressure range so normalization
    // is correct for any tablet, with no hardcoded maximum.
    final realMax = _readEvdevPressureMax(path);
    if (realMax != null && realMax > 0) _evdevPmax = realMax.toDouble();
    CrashLogger.append('[Pen] pressure via evdev $path '
        '(max ${_evdevPmax.toStringAsFixed(0)}'
        '${realMax != null ? "" : ", fallback"})');
    _evdevRunning = true;
    _evdevPump(path);
  }

  /// Read the maximum value of the ABS_PRESSURE axis directly from the kernel
  /// via the EVIOCGABS ioctl. Tablets differ wildly (≈1023 / 2047 / 8191 /
  /// 32767), so this makes pressure normalization correct for ANY device
  /// instead of assuming one model's full-scale. Returns null on any failure
  /// (the caller then keeps the auto-bumping fallback default).
  static int? _readEvdevPressureMax(String path) {
    if (!Platform.isLinux) return null;
    try {
      final libc = DynamicLibrary.open('libc.so.6');
      final openF = libc.lookupFunction<Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)>('open');
      final ioctlF = libc.lookupFunction<
          Int32 Function(Int32, UnsignedLong, Pointer<Int32>),
          int Function(int, int, Pointer<Int32>)>('ioctl');
      final closeF = libc
          .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
      final cpath = path.toNativeUtf8();
      int fd;
      try {
        fd = openF(cpath, 0); // O_RDONLY
      } finally {
        malloc.free(cpath);
      }
      if (fd < 0) return null;
      // struct input_absinfo = 6×s32 {value,minimum,maximum,fuzz,flat,resolution}
      final buf = calloc<Int32>(6);
      try {
        // EVIOCGABS(ABS_PRESSURE) = _IOR('E', 0x40+0x18, struct input_absinfo)
        const req = (2 << 30) | (24 << 16) | (0x45 << 8) | 0x58; // 0x80184558
        if (ioctlF(fd, req, buf) < 0) return null;
        final max = buf[2]; // index 2 = maximum
        return max > 0 ? max : null;
      } finally {
        calloc.free(buf);
        closeF(fd);
      }
    } catch (_) {
      return null;
    }
  }

  /// Async read loop over the char device. Each `read()` runs on the IO
  /// thread pool (blocks there until the kernel has events), so the UI
  /// isolate is never blocked. The device never reaches EOF while open.
  static Future<void> _evdevPump(String path) async {
    try {
      _evdevRaf = await File(path).open();
    } catch (e) {
      _evdevRunning = false;
      CrashLogger.append('[Pen] evdev open $path failed: $e');
      return;
    }
    final raf = _evdevRaf!;
    while (_evdevRunning) {
      Uint8List bytes;
      try {
        bytes = await raf.read(_evRecord * 16);
      } catch (_) {
        break; // closed during read (e.g. unregister)
      }
      if (bytes.isEmpty) break; // device went away
      _onEvdevChunk(bytes);
    }
    try {
      await raf.close();
    } catch (_) {}
  }

  // struct input_event on 64-bit Linux: timeval(16) + type(u16@16) +
  // code(u16@18) + value(i32@20) = 24 bytes.
  static const int _evRecord = 24;
  static const int _evKey = 0x01, _evAbs = 0x03;
  static const int _absPressure = 0x18, _btnToolPen = 0x140;

  static void _onEvdevChunk(List<int> chunk) {
    final data = _evdevLeftover.isEmpty
        ? chunk
        : (<int>[..._evdevLeftover, ...chunk]);
    var off = 0;
    while (data.length - off >= _evRecord) {
      final bd = ByteData.sublistView(
          Uint8List.fromList(data.sublist(off, off + _evRecord)));
      final type = bd.getUint16(16, Endian.host);
      final code = bd.getUint16(18, Endian.host);
      final value = bd.getInt32(20, Endian.host);
      off += _evRecord;
      if (type == _evAbs && code == _absPressure) {
        if (value > _evdevPmax) _evdevPmax = value.toDouble();
        _setPressure((value / _evdevPmax).clamp(0.0, 1.0));
      } else if (type == _evKey && code == _btnToolPen && value == 0) {
        _setPressure(0.0); // pen lifted
      }
    }
    _evdevLeftover = data.sublist(off);
  }

  static void _setPressure(double p) {
    _pressure = p;
  }

  /// Current pen pressure in [0, 1], or -1 if no sample has arrived yet.
  ///
  /// IMPORTANT: evdev reports ABSOLUTE pressure and only on CHANGE, and it
  /// drops to 0 on pen-lift (ABS_PRESSURE→0 / BTN_TOOL_PEN up). So the cached
  /// value is the live truth and must NOT be age-expired: a steady-pressure
  /// stroke emits no new events for >100ms, and an age gate would then read
  /// it as 0 and collapse the line width mid-stroke (the "thin dips" bug).
  /// [maxAgeMs] is kept for source compatibility but intentionally ignored.
  static double latest({int maxAgeMs = 120}) {
    return _pressure < 0 ? -1 : _pressure;
  }

  static double get tiltX => _tiltX;
  static double get tiltY => _tiltY;

  static void unregister() {
    if (!_registered) return;
    _channel.setMethodCallHandler(null);
    _evdevRunning = false;
    _evdevRaf?.close();
    _evdevRaf = null;
    _evdevLeftover = const [];
    _registered = false;
    _pressure = -1;
    _serverPressureLogged = false;
  }
}
