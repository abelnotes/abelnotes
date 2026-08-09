import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

/// Sanitise a string for use inside a filename on every platform we ship on
/// (Windows is the strict one: no `\ / : * ? " < > |` and no trailing dots or
/// spaces). Returns a non-empty placeholder when nothing survives the filter.
String sanitiseForFilename(String raw) {
  var out = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  while (out.endsWith('.') || out.endsWith(' ')) {
    out = out.substring(0, out.length - 1).trimRight();
  }
  return out.isEmpty ? 'Quaderno' : out;
}

/// Write [data] wherever the user wants it. iOS/macOS go through the system
/// share sheet (FilePicker.saveFile is broken there); everything else gets a
/// native save dialog.
Future<void> saveOrShareFile(
  BuildContext context, {
  required String fileName,
  required Uint8List data,
  required String mimeType,
}) async {
  if (io.Platform.isIOS || io.Platform.isMacOS) {
    // Read the anchor before any await. iPad needs a non-zero rect for the
    // share-sheet popover or SharePlus throws, and MediaQuery must not be
    // touched across an async gap. The screen centre is always in view.
    final origin = _shareOriginRect(context);
    final dir = await io.Directory.systemTemp.createTemp('abelnotes_export');
    final file = io.File('${dir.path}/$fileName');
    await file.writeAsBytes(data, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: fileName,
        sharePositionOrigin: origin,
      ),
    );
    return;
  }

  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: AppLocalizations.of(context).csSaveFileDialogTitle(fileName),
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [fileName.split('.').last],
  );
  if (savePath != null) {
    await io.File(savePath).writeAsBytes(data, flush: true);
  }
}

Rect _shareOriginRect(BuildContext context) {
  final size = MediaQuery.of(context).size;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 40,
    height: 40,
  );
}
