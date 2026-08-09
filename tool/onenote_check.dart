// Diagnostic for the OneNote FFI bridge: reports whether the native library
// loads on this platform and what the parser makes of a given file. The app
// only ever surfaces a one-line message, so this is where you look when an
// import fails.
//
//   dart run tool/onenote_check.dart <file.one> [more files...]
//
// Run it from the repo root — the bridge is looked up relative to the CWD when
// not running from a release bundle.

import 'dart:io';

import 'package:abelnotes/features/import/data/onenote_ffi.dart';

void main(List<String> args) {
  stdout.writeln('platform : ${Platform.operatingSystem}');
  stdout.writeln('bridge   : ${OneNoteBridge.available ? "loaded" : "NOT FOUND"}');
  if (!OneNoteBridge.available) {
    stdout.writeln('\nBuild it with native/build_onenote_bridge.sh (needs Rust).');
    exitCode = 1;
    return;
  }

  if (args.isEmpty) {
    stdout.writeln('\nPass one or more .one / .onetoc2 / .onepkg files.');
    return;
  }

  for (final path in args) {
    stdout.writeln('\n── ${path.split(RegExp(r"[\\/]")).last}');
    if (!File(path).existsSync()) {
      stdout.writeln('   missing on disk');
      continue;
    }
    stdout.writeln('   size: ${(File(path).lengthSync() / 1024).round()} KB');
    try {
      final tree = OneNoteBridge.parseFile(path);
      final sections = tree['sections'];
      stdout.writeln('   OK   keys=${tree.keys.toList()}');
      if (sections is List) {
        stdout.writeln('   sections: ${sections.length}');
        for (final section in sections) {
          if (section is! Map) continue;
          final pages = section['pages'];
          stdout.writeln('     - "${section['name']}" '
              'pages=${pages is List ? pages.length : "?"}');
        }
      }
    } catch (e) {
      stdout.writeln('   FAIL $e');
    }
  }
}
