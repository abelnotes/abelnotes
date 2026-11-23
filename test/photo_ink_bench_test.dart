// Photo to ink over a folder of photos, for an external bench: strokes
// written as JSON in photo pixels. Skips unless ABELNOTES_PHOTO_BENCH and
// ABELNOTES_PHOTO_BENCH_OUT are set.
import 'dart:convert';
import 'dart:io';

import 'package:abelnotes/features/canvas/data/photo_ink/photo_ink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final env = Platform.environment;
  final dir = env['ABELNOTES_PHOTO_BENCH'], out = env['ABELNOTES_PHOTO_BENCH_OUT'];

  test('photos through photo to ink', () {
    Directory(out!).createSync(recursive: true);
    final only = env['ABELNOTES_PHOTO_BENCH_ONLY']?.split(',').toSet();
    final files = Directory(dir!)
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(f.path))
        .where((f) => only == null || only.contains(f.uri.pathSegments.last.split('.').first))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final im = img.decodeImage(f.readAsBytesSync())!.convert(numChannels: 4);
      photoInkLaps = {};
      final watch = Stopwatch()..start();
      final r = photoToInk(im.getBytes(order: img.ChannelOrder.rgba), im.width, im.height);
      final ms = watch.elapsedMilliseconds;
      final m = r.toSource;
      List<double> toSrc(List<double> p) => [
            for (var i = 0; i + 1 < p.length; i += 2)
              for (final v in () {
                final z = m[6] * p[i] + m[7] * p[i + 1] + m[8];
                return [(m[0] * p[i] + m[1] * p[i + 1] + m[2]) / z, (m[3] * p[i] + m[4] * p[i + 1] + m[5]) / z];
              }())
                (v * 10).round() / 10
          ];
      final name = f.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      File('$out/$name.json').writeAsStringSync(jsonEncode({
        'ms': ms,
        'rectified': r.rectified,
        'strokes': [
          for (final s in r.strokes)
            {'p': toSrc(s.points), 'w': s.width, 'c': s.color, 'hl': s.highlighter}
        ],
      }));
      // ignore: avoid_print
      print('$name ${im.width}x${im.height} ${r.strokes.length} strokes ${ms}ms $photoInkLaps');
    }
  }, skip: dir == null || out == null);
}
