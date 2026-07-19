import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:abelnotes/features/import/data/frontmatter.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/markdown_block_parser.dart';

/// Parses a Notion "Markdown & CSV" export zip into an
/// [ImportedNotebookDraft]. Notion appends a 32-hex page id to every file
/// and folder name — that suffix is stripped for titles and used to resolve
/// the URL-encoded relative links between pages and assets.
class NotionImporter {
  /// ` 21f0a8b3c4d5e6f7a8b9c0d1e2f3a4b5` name suffix (space + 32 hex).
  static final _idSuffix = RegExp(r' [0-9a-f]{32}$');

  /// Internal page links in the markdown: `[text](Page%20<id>.md)`.
  static final _mdLink = RegExp(r'\[([^\]]*)\]\(([^)\s]+\.md)\)');

  static const _imageExts = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'
  };

  final _uuid = const Uuid();

  /// True when the zip's entry names carry Notion's 32-hex id suffixes.
  static bool looksLikeNotionExport(Archive archive) {
    return archive.files.any((f) {
      final base = p.basenameWithoutExtension(f.name);
      return _idSuffix.hasMatch(base) ||
          p.split(f.name).any((seg) => _idSuffix.hasMatch(seg));
    });
  }

  Future<ImportedNotebookDraft> parse(
    Uint8List zipBytes, {
    required String exportName,
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(const ImportProgress(phase: ImportPhase.scanning));

    // Flatten the archive, unpacking one level of nested Export-*.zip parts
    // (Notion splits big exports).
    final entries = <String, Uint8List>{};
    void addArchive(Archive archive, String prefix) {
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = p.normalize(p.join(prefix, f.name));
        if (name.startsWith('..')) continue; // zip-slip guard
        final data = f.content as List<int>;
        if (p.extension(name).toLowerCase() == '.zip' && prefix.isEmpty) {
          try {
            addArchive(ZipDecoder().decodeBytes(data),
                p.basenameWithoutExtension(name));
            continue;
          } catch (_) {
            // Not a readable nested zip: keep it as an opaque entry.
          }
        }
        entries[name] = Uint8List.fromList(data);
      }
    }

    addArchive(ZipDecoder().decodeBytes(zipBytes), '');

    final mdPaths = entries.keys
        .where((k) => p.extension(k).toLowerCase() == '.md')
        .toList()
      ..sort();
    final csvPaths = entries.keys
        .where((k) => p.extension(k).toLowerCase() == '.csv')
        .toList()
      ..sort();
    if (mdPaths.isEmpty && csvPaths.isEmpty) {
      throw const FormatException(
          'lo zip non contiene file .md/.csv (serve un export Notion "Markdown & CSV")');
    }

    // Prefer X_all.csv over X.csv when both exist (same database, the _all
    // variant includes every view's rows).
    final csvSet = csvPaths.toSet();
    final dedupedCsv = csvPaths.where((path) {
      if (path.endsWith('_all.csv')) return true;
      final allVariant = '${path.substring(0, path.length - 4)}_all.csv';
      return !csvSet.contains(allVariant);
    }).toList();

    String cleanSegment(String seg) {
      final ext = p.extension(seg);
      final base =
          ext.isEmpty ? seg : seg.substring(0, seg.length - ext.length);
      return base
          .replaceAll(RegExp(r'_all$'), '')
          .replaceAll(_idSuffix, '');
    }

    String chapterTitle(String path) =>
        p.split(path).map(cleanSegment).join(' / ');

    final issues = <ImportIssue>[];
    final assets = <String, Uint8List>{};
    final assetKeyByHash = <String, String>{};
    final tags = <String>{};
    final chapters = <ImportedChapterDraft>[];
    final total = mdPaths.length + dedupedCsv.length;
    var done = 0;

    for (final mdPath in mdPaths) {
      if (isCancelled?.call() ?? false) break;
      final title = chapterTitle(mdPath);
      onProgress?.call(ImportProgress(
        phase: ImportPhase.parsing,
        current: done++,
        total: total,
        detail: title,
      ));

      final fm = stripFrontmatter(utf8.decode(entries[mdPath]!,
          allowMalformed: true));
      tags.addAll(fm.tags);

      // Rewrite internal page links (…<id>.md) to the inert internal-link
      // scheme so they render as blue spans instead of ` (long ugly url)`.
      final markdown = fm.body.replaceAllMapped(_mdLink, (m) {
        final label = m.group(1)!;
        return '[$label](${kInternalLinkScheme}n)';
      });

      Uint8List? lookup(String src) {
        final decoded = p.normalize(Uri.decodeFull(src));
        final relToMd = p.normalize(p.join(p.dirname(mdPath), decoded));
        return entries[relToMd] ?? entries[decoded];
      }

      ImageBlock? resolveImage(String src, String? alt) {
        if (src.startsWith('http://') || src.startsWith('https://')) {
          issues.add(ImportIssue(
            source: title,
            severity: ImportIssueSeverity.info,
            message: 'immagine remota non scaricata: $src',
          ));
          return null;
        }
        final bytes = lookup(src);
        if (bytes == null) return null;
        final ext = p.extension(Uri.decodeFull(src)).toLowerCase();
        if (!_imageExts.contains(ext) || ext == '.svg') {
          issues.add(ImportIssue(
            source: title,
            severity: ImportIssueSeverity.info,
            message: 'allegato non supportato (v1 solo immagini raster): $src',
          ));
          return null;
        }
        final hash = sha1.convert(bytes).toString();
        var key = assetKeyByHash[hash];
        if (key == null) {
          key =
              '${_uuid.v4()}_${p.basename(Uri.decodeFull(src)).replaceAll(_idSuffix, '')}';
          assetKeyByHash[hash] = key;
          assets[key] = bytes;
        }
        final info = img.findDecoderForData(bytes)?.startDecode(bytes);
        if (info == null) return null;
        return ImageBlock(assetKey: key, pxW: info.width, pxH: info.height);
      }

      final parser = MarkdownParser(
        resolveImage: resolveImage,
        onIssue: issues.add,
        sourceName: title,
      );
      chapters.add(ImportedChapterDraft(
        title: title,
        blocks: parser.parse(markdown),
      ));
      await Future<void>.delayed(Duration.zero);
    }

    for (final csvPath in dedupedCsv) {
      if (isCancelled?.call() ?? false) break;
      final title = chapterTitle(csvPath);
      onProgress?.call(ImportProgress(
        phase: ImportPhase.parsing,
        current: done++,
        total: total,
        detail: title,
      ));
      try {
        final rows =
            Csv().decode(utf8.decode(entries[csvPath]!, allowMalformed: true));
        if (rows.isEmpty) continue;
        chapters.add(ImportedChapterDraft(
          title: title,
          blocks: [
            TableBlock(
              rows: [
                for (final r in rows)
                  [for (final cell in r) cell.toString().trim()]
              ],
            ),
          ],
        ));
      } catch (e) {
        issues.add(ImportIssue(
          source: title,
          severity: ImportIssueSeverity.error,
          message: 'CSV illeggibile: $e',
        ));
      }
      await Future<void>.delayed(Duration.zero);
    }

    if (chapters.isEmpty) {
      throw const FormatException('nessun contenuto importabile nello zip');
    }

    // Notebook title: the single top-level export folder if there is one,
    // otherwise the zip's own name.
    final topDirs = mdPaths
        .followedBy(dedupedCsv)
        .map((path) => p.split(path).first)
        .toSet();
    final title = topDirs.length == 1 && p.split(mdPaths.firstOrNull ?? dedupedCsv.first).length > 1
        ? cleanSegment(topDirs.first)
        : cleanSegment(p.basenameWithoutExtension(exportName));

    return ImportedNotebookDraft(
      title: title.isEmpty ? 'Notion' : title,
      tags: tags.toList()..sort(),
      chapters: chapters,
      assets: assets,
      issues: issues,
    );
  }
}
