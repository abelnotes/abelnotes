// Compress existing PDF-raster PNG assets to JPEG q=85 in-place.
//
// Single-user migration helper. Walks the local Nextcloud mirror at
// ~/Nextcloud/AbelNotes/_delta/<notebookId>/assets/, finds every
// PDF-raster PNG (filename matches `*.pdf_pXX.png`), decodes it, and
// rewrites the same file with JPEG bytes. Filename keeps the .png
// extension because the app's decoder reads magic bytes, not the
// suffix — so older builds load the migrated bytes unchanged.
//
// Usage (with the app CLOSED to avoid race writes):
//   cd <project root>
//   dart run tool/compress_pdf_assets.dart
//
// Or override the root:
//   dart run tool/compress_pdf_assets.dart /path/to/Nextcloud/AbelNotes
//
// Idempotent: files that are already JPEG (magic 0xFFD8) are skipped.
// PNG files that compress to a LARGER JPEG (line art with sharp
// edges) are also skipped — original is kept.
//
// After running, Nextcloud's desktop client picks up the modified
// files and syncs them to the server. Other devices then receive
// the new bytes on their next pull (ETag mismatch triggers a
// re-download of just the changed assets — typically ~85% smaller).

import 'dart:io';
import 'package:image/image.dart' as image_lib;

void main(List<String> args) async {
  final home = Platform.environment['HOME'];
  final defaultRoot =
      home == null ? null : '$home/Nextcloud/AbelNotes';
  final root = args.isNotEmpty ? args[0] : defaultRoot;
  if (root == null) {
    stderr.writeln('Cannot resolve AbelNotes root. Pass it as argument:');
    stderr.writeln(
        '  dart run tool/compress_pdf_assets.dart /path/to/AbelNotes');
    exit(2);
  }

  final deltaDir = Directory('$root/_delta');
  if (!await deltaDir.exists()) {
    stderr.writeln('Delta dir not found: ${deltaDir.path}');
    stderr.writeln('Is the Nextcloud client running and have you synced once?');
    exit(2);
  }

  // Match only PDF-raster files. The app names them
  // `<uuid>_<originalName>.pdf_p<N>.png`. Other PNGs in the assets dir
  // (user screenshots, photos pasted in) are left alone — they may
  // legitimately need transparency or sharp line art that JPEG ruins.
  final pdfRasterRegex = RegExp(r'\.pdf_p\d+\.png$');

  print('Scanning ${deltaDir.path} for PDF raster PNGs...');
  print('');

  var converted = 0;
  var alreadyJpeg = 0;
  var notPdfRaster = 0;
  var skippedNotSmaller = 0;
  var errored = 0;
  var savedBytes = 0;
  var totalScanned = 0;

  await for (final entity in deltaDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.png') && !entity.path.endsWith('.jpg')) {
      continue;
    }
    totalScanned++;

    final bytes = await entity.readAsBytes();
    if (bytes.length < 4) continue;

    // Magic-byte detection (more reliable than extension).
    final isPng = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;

    if (isJpeg) {
      alreadyJpeg++;
      continue;
    }
    if (!isPng) {
      // Unknown format; skip defensively.
      continue;
    }

    // Restrict to PDF-raster filename pattern.
    if (!pdfRasterRegex.hasMatch(entity.path)) {
      notPdfRaster++;
      continue;
    }

    try {
      final decoded = image_lib.decodePng(bytes);
      if (decoded == null) {
        errored++;
        stderr.writeln('  decode failed: ${entity.path}');
        continue;
      }
      final jpegBytes = image_lib.encodeJpg(decoded, quality: 85);

      if (jpegBytes.length >= bytes.length) {
        skippedNotSmaller++;
        continue;
      }

      // Atomic rewrite: write to a temp file in the same dir, then rename.
      // Same-filesystem rename is atomic on POSIX — protects against the
      // Nextcloud client snapshotting a half-written file.
      final tempPath = '${entity.path}.tmp.compress';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(jpegBytes);
      await tempFile.rename(entity.path);

      savedBytes += (bytes.length - jpegBytes.length);
      converted++;
      final beforeKb = (bytes.length / 1024).round();
      final afterKb = (jpegBytes.length / 1024).round();
      print('✓ ${entity.path.substring(deltaDir.path.length + 1)}: '
          '$beforeKb KB → $afterKb KB');
    } catch (e) {
      errored++;
      stderr.writeln('  error on ${entity.path}: $e');
    }
  }

  print('');
  print('═══ Summary ═══');
  print('  Files scanned:        $totalScanned');
  print('  Converted:            $converted');
  print('  Already JPEG:         $alreadyJpeg');
  print('  Not PDF-raster (skip): $notPdfRaster');
  print('  Skipped (not smaller): $skippedNotSmaller');
  print('  Errors:               $errored');
  print('  Space saved:          ${(savedBytes / 1024 / 1024).toStringAsFixed(1)} MB');
  print('');
  if (converted > 0) {
    print('Nextcloud will sync the modified files to the server.');
    print('Other devices will re-download just the changed assets on');
    print('their next pull (ETag mismatch). Local .ncnote caches will');
    print('be rebuilt with the new bytes on the next save in each device.');
  }
}
