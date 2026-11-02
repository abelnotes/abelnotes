@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:abelnotes/ui/services/file_export.dart';
import 'package:abelnotes/core/platform/io.dart' as io;

// Deliberately inherits the throwing saveFile implementation from file_picker
// 8.x. The regression must not silently start calling that method again.
class _UnavailableSavePicker extends FilePicker {}

void main() {
  test('web file reads return independent, exact-length buffers', () async {
    final file = io.File('/export-test/asset.bin');
    addTearDown(() => file.deleteSync());
    final view = Uint8List.sublistView(
        Uint8List.fromList([80, 75, 1, 2, 255, 99]), 2, 5);
    file.writeAsBytesSync(view);
    for (final bytes in [file.readAsBytesSync(), await file.readAsBytes()]) {
      expect(bytes, orderedEquals([1, 2, 255]));
      expect(bytes.offsetInBytes, 0);
      expect(bytes.buffer.lengthInBytes, bytes.lengthInBytes);
      bytes[0] = 42;
      expect(file.readAsBytesSync(), orderedEquals([1, 2, 255]));
    }
  });

  test('image assets read from archive views retain their pixels', () async {
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGM0z7vznwEPYMInOXwUAACVwwKQrT3XsgAAAABJRU5ErkJggg==');
    final archive = Uint8List.fromList([80, 75, 3, 4, ...png, 99]);
    final file = io.File('/export-test/image.png');
    addTearDown(() => file.deleteSync());
    file.writeAsBytesSync(Uint8List.sublistView(archive, 4, 4 + png.length));
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);
    expect(frame.image.width, 8);
    expect(frame.image.height, 8);
    final pixels = (await frame.image.toByteData())!;
    expect(pixels.buffer.asUint8List(pixels.offsetInBytes, 4),
        orderedEquals([55, 110, 220, 255]));
  });

  for (final sample in [
    ('工作日志 #1.abelnote', 'application/zip', <int>[80, 75, 0, 255, 128, 1]),
    ('笔记.pdf', 'application/pdf', <int>[37, 80, 68, 70, 45, 0, 255]),
    ('页面.png', 'image/png', <int>[137, 80, 78, 71, 13, 10, 26, 10]),
    ('abelnotes_library.zip', 'application/zip', <int>[80, 75, 3, 4, 255]),
    ('empty.abelnote', 'application/zip', <int>[]),
    ('view.abelnote', 'application/zip', <int>[0, 255, 128, 42]),
  ]) {
    testWidgets('downloads ${sample.$1} without the native picker',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }));
      FilePicker? originalPicker;
      try {
        originalPicker = FilePicker.platform;
      } catch (_) {
        // The browser test runner may not register native plugins.
      }
      FilePicker.platform = _UnavailableSavePicker();
      addTearDown(() {
        if (originalPicker != null) FilePicker.platform = originalPicker;
      });
      String? blobUrl;
      String? suggestedName;
      final listener = ((web.Event event) {
        final anchor =
            web.document.querySelector('a[download]') as web.HTMLAnchorElement?;
        if (anchor != null && event.target == anchor) {
          if (anchor.download.isNotEmpty) {
            event.preventDefault(); // Inspect bytes without downloading in CI.
            blobUrl = anchor.href;
            suggestedName = anchor.download;
          }
        }
      }).toJS;
      web.document.addEventListener('click', listener);
      addTearDown(() => web.document.removeEventListener('click', listener));

      final bytes = sample.$1 == 'view.abelnote'
          ? Uint8List.sublistView(Uint8List.fromList([99, ...sample.$3, 98]), 1,
              sample.$3.length + 1)
          : Uint8List.fromList(sample.$3);
      await saveOrShareFile(context,
          fileName: sample.$1, data: bytes, mimeType: sample.$2);
      expect(suggestedName, sample.$1);
      expect(blobUrl, startsWith('blob:'));
      expect(web.document.querySelector('a[download]'), isNull);
      await tester.runAsync(() async {
        final response = await web.window.fetch(blobUrl!.toJS).toDart;
        expect(response.headers.get('content-type'), sample.$2);
        final buffer = await response.arrayBuffer().toDart;
        expect(buffer.toDart.asUint8List(), orderedEquals(bytes));
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {
        await expectLater(
            web.window.fetch(blobUrl!.toJS).toDart, throwsA(anything));
      });
    });
  }
}
