import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/services/file_export.dart';

class _SavePicker extends FilePicker {
  String? path;
  String? name;
  Uint8List? data;
  List<String>? extensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    name = fileName;
    data = bytes;
    extensions = allowedExtensions;
    return path;
  }
}

void main() {
  test('filenames retain Unicode but remove reserved characters', () {
    expect(
        sanitiseForFilename('工作日志: 11/02?.abelnote'), '工作日志_ 11_02_.abelnote');
    expect(sanitiseForFilename(' .. '), 'AbelNotes');
  });

  for (final cancel in [false, true]) {
    testWidgets('desktop save preserves bytes (cancel=$cancel)',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      final directory = Directory.systemTemp.createTempSync('file_export_test');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/工作日志.abelnote');
      final picker = _SavePicker()..path = cancel ? null : file.path;
      FilePicker? original;
      try {
        original = FilePicker.platform;
      } catch (_) {
        // Native plugins are not registered by the headless widget runner.
      }
      FilePicker.platform = picker;
      addTearDown(() {
        if (original != null) FilePicker.platform = original;
      });
      final bytes = Uint8List.fromList([80, 75, 0, 255, 128]);
      await tester.runAsync(() => saveOrShareFile(context,
          fileName: '工作日志.abelnote', data: bytes, mimeType: 'application/zip'));
      expect(picker.name, '工作日志.abelnote');
      expect(picker.data, same(bytes));
      expect(picker.extensions, ['abelnote']);
      expect(file.existsSync(), !cancel);
      if (!cancel) expect(file.readAsBytesSync(), orderedEquals(bytes));
    });
  }
}
