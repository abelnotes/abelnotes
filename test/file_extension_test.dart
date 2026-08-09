import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/file_open_receiver.dart';

void main() {
  group('notebook file extension', () {
    test('exports and the file association use the AbelNotes spelling', () {
      expect(AppConfig.fileExtension, '.abelnote');
    });

    test('storage and WebDAV keep the pre-rename spelling', () {
      // Renaming these would orphan local notebooks and make other devices
      // miss everything already on the user's server.
      expect(AppConfig.storageExtension, '.ncnote');
    });

    test('both spellings are recognised, case-insensitively', () {
      expect(AppConfig.isNotebookPath('/tmp/Appunti.abelnote'), isTrue);
      expect(AppConfig.isNotebookPath('/tmp/Appunti.ncnote'), isTrue);
      expect(AppConfig.isNotebookPath(r'C:\Users\me\Appunti.ABELNOTE'), isTrue);
      expect(AppConfig.isNotebookPath(r'C:\Users\me\Appunti.NCNOTE'), isTrue);
    });

    test('unrelated files are rejected', () {
      expect(AppConfig.isNotebookPath('/tmp/report.pdf'), isFalse);
      expect(AppConfig.isNotebookPath('/tmp/archive.zip'), isFalse);
      expect(AppConfig.isNotebookPath('/tmp/ncnote'), isFalse);
      expect(AppConfig.isNotebookPath(''), isFalse);
    });
  });

  group('FileOpenReceiver.notebookPathFrom', () {
    test('ignores flags and files that do not exist', () {
      expect(
        FileOpenReceiver.notebookPathFrom(
            ['--observatory-port=0', '/does/not/exist.abelnote']),
        isNull,
      );
    });

    test('picks a real notebook of either spelling', () async {
      final dir = await Directory.systemTemp.createTemp('abelnotes_ext_test');
      addTearDown(() => dir.delete(recursive: true));

      final current = File('${dir.path}/Nuovo.abelnote')..writeAsBytesSync([1]);
      final legacy = File('${dir.path}/Vecchio.ncnote')..writeAsBytesSync([1]);

      expect(FileOpenReceiver.notebookPathFrom(['--flag', current.path]),
          current.path);
      expect(FileOpenReceiver.notebookPathFrom([legacy.path]), legacy.path);
    });
  });
}
