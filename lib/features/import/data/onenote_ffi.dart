import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Thin dart:ffi binding to the Rust bridge (native/onenote_bridge) that
/// parses OneNote files via the `onenote_parser` crate (MPL-2.0) and returns
/// a JSON document tree. Desktop-only: the shared library is bundled with
/// the desktop builds; [available] is false elsewhere.
class OneNoteBridge {
  OneNoteBridge._();

  static DynamicLibrary? _lib;
  static bool _loadTried = false;

  static String get _libFileName {
    if (Platform.isWindows) return 'onenote_bridge.dll';
    if (Platform.isMacOS) return 'libonenote_bridge.dylib';
    return 'libonenote_bridge.so';
  }

  /// Search order: next to the executable (release bundle's lib dir), then
  /// the in-repo build/prebuilt paths used during `flutter run`.
  static Iterable<String> get _candidatePaths sync* {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    yield p.join(exeDir, 'lib', _libFileName);
    yield p.join(exeDir, _libFileName);
    yield p.join(Directory.current.path, 'native', 'onenote_bridge', 'target',
        'release', _libFileName);
    yield p.join(Directory.current.path, 'native', 'prebuilt',
        '${Platform.operatingSystem}-x64', _libFileName);
  }

  static DynamicLibrary? _load() {
    if (_loadTried) return _lib;
    _loadTried = true;
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      return null;
    }
    for (final path in _candidatePaths) {
      if (!File(path).existsSync()) continue;
      try {
        _lib = DynamicLibrary.open(path);
        break;
      } catch (_) {
        // Wrong arch / corrupt file: try the next candidate.
      }
    }
    return _lib;
  }

  /// Whether the native bridge is present on this platform/build.
  static bool get available => _load() != null;

  /// Parse [filePath] (.one / .onetoc2) and return the decoded JSON tree.
  /// Throws [FormatException] with the bridge's error message on failure.
  static Map<String, dynamic> parseFile(String filePath) {
    final lib = _load();
    if (lib == null) {
      throw const FormatException(
          'bridge OneNote non disponibile su questa piattaforma');
    }
    final parse = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)>('onenote_parse_file');
    final free = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)>('onenote_free_string');

    final pathPtr = filePath.toNativeUtf8();
    Pointer<Utf8> resultPtr = nullptr;
    try {
      resultPtr = parse(pathPtr);
      if (resultPtr == nullptr) {
        throw const FormatException('bridge OneNote: risposta nulla');
      }
      final jsonStr = resultPtr.toDartString();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is String) throw FormatException(error);
      return decoded;
    } finally {
      malloc.free(pathPtr);
      if (resultPtr != nullptr) free(resultPtr);
    }
  }
}
