import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/config/japanese_font.dart';
import 'package:abelnotes/features/canvas/data/pdf_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetJapaneseFontForTest);

  test('callers that need the font at once share one load', () async {
    var reads = 0;
    final bytes = Completer<ByteData>();
    japaneseFontBytes = () {
      reads++;
      return bytes.future;
    };
    final a = ensureJapaneseFont();
    final b = ensureJapaneseFont();
    bytes.complete(await rootBundle.load(japaneseFontAsset));
    expect(await Future.wait([a, b]), [true, true]);
    expect(await ensureJapaneseFont(), isTrue);
    expect(reads, 1);
    expect(japaneseFontReady, isTrue);
  });

  test('a failed load falls back quietly and is not retried at once',
      () async {
    var reads = 0;
    japaneseFontBytes = () {
      reads++;
      return Future.error(StateError('offline'));
    };
    expect(await ensureJapaneseFont(), isFalse);
    expect(await ensureJapaneseFont(), isFalse);
    expect(reads, 1);
    expect(japaneseFontReady, isFalse);
  });

  test('PDF export still works when the font cannot be read', () async {
    japaneseFontBytes = () => Future.error(StateError('offline'));
    final bytes = await buildPdfDocument([
      const PdfExportPage(width: 300, height: 200, runs: [
        PdfExportRun(text: '日本語のノート', x: 20, y: 20, width: 200, height: 16),
      ]),
    ]);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(bytes), isNot(contains('/NotoSansJP')));
  });

  test('Latin-only export never reads the font', () async {
    var reads = 0;
    japaneseFontBytes = () {
      reads++;
      return rootBundle.load(japaneseFontAsset);
    };
    await buildPdfDocument([
      const PdfExportPage(width: 300, height: 200, runs: [
        PdfExportRun(text: 'hello', x: 20, y: 20, width: 100, height: 16),
      ]),
    ]);
    expect(reads, 0);
  });
}
