import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:abelnotes/features/import/data/frontmatter.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/markdown_block_parser.dart';

/// Parses an Obsidian vault directory into an [ImportedNotebookDraft]:
/// one chapter per .md file (path-prefixed titles preserve the folder
/// hierarchy), vault attachments resolved Obsidian-style (exact path first,
/// then unique basename anywhere in the vault).
class ObsidianImporter {
  static const _imageExts = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'
  };

  /// `![[embed]]` / `[[link|alias]]` — converted to standard Markdown before
  /// parsing so the CommonMark parser handles everything else.
  static final _embedPattern = RegExp(r'!\[\[([^\]\[]+?)\]\]');
  static final _wikilinkPattern = RegExp(r'\[\[([^\]\[]+?)\]\]');

  final _uuid = const Uuid();

  Future<ImportedNotebookDraft> parse(
    String vaultPath, {
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final root = Directory(vaultPath);
    final issues = <ImportIssue>[];
    final assets = <String, Uint8List>{};
    final assetKeyByHash = <String, String>{};
    final tags = <String>{};

    onProgress?.call(const ImportProgress(phase: ImportPhase.scanning));

    final mdFiles = <File>[];
    final attachmentIndex = <String, File>{}; // vault-relative path (lower)
    final basenameIndex = <String, List<File>>{}; // basename (lower)
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: vaultPath);
      // Skip hidden trees (.obsidian, .trash, .git, …).
      if (p.split(rel).any((seg) => seg.startsWith('.'))) continue;
      if (p.extension(entity.path).toLowerCase() == '.md') {
        mdFiles.add(entity);
      } else {
        attachmentIndex[rel.toLowerCase()] = entity;
        basenameIndex
            .putIfAbsent(p.basename(entity.path).toLowerCase(), () => [])
            .add(entity);
      }
    }
    mdFiles.sort((a, b) => a.path.compareTo(b.path));
    if (mdFiles.isEmpty) {
      throw const FormatException('nessun file .md nella cartella scelta');
    }

    /// Obsidian "shortest path" resolution: exact vault-relative path, then
    /// path relative to the current note, then unique basename.
    File? resolveAttachment(String target, String mdDir) {
      final decoded = Uri.decodeFull(target).replaceAll('\\', '/');
      final lower = decoded.toLowerCase();
      final exact = attachmentIndex[lower];
      if (exact != null) return exact;
      final relToNote =
          p.relative(p.normalize(p.join(mdDir, decoded)), from: vaultPath);
      final byNote = attachmentIndex[relToNote.toLowerCase()];
      if (byNote != null) return byNote;
      final byName = basenameIndex[p.basename(lower)];
      if (byName != null && byName.isNotEmpty) return byName.first;
      return null;
    }

    final chapters = <ImportedChapterDraft>[];
    for (var i = 0; i < mdFiles.length; i++) {
      if (isCancelled?.call() ?? false) break;
      final file = mdFiles[i];
      final rel = p.relative(file.path, from: vaultPath);
      final title =
          p.split(rel).join(' / ').replaceAll(RegExp(r'\.md$'), '');
      onProgress?.call(ImportProgress(
        phase: ImportPhase.parsing,
        current: i,
        total: mdFiles.length,
        detail: title,
      ));

      String raw;
      try {
        raw = await file.readAsString();
      } catch (e) {
        issues.add(ImportIssue(
          source: rel,
          severity: ImportIssueSeverity.error,
          message: 'file illeggibile: $e',
        ));
        continue;
      }

      final fm = stripFrontmatter(raw);
      tags.addAll(fm.tags);
      final markdown = _rewriteWikiSyntax(fm.body, rel, issues);

      ImageBlock? resolveImage(String src, String? alt) {
        if (src.startsWith('http://') || src.startsWith('https://')) {
          issues.add(ImportIssue(
            source: rel,
            severity: ImportIssueSeverity.info,
            message: 'immagine remota non scaricata: $src',
          ));
          return null;
        }
        final f = resolveAttachment(src, p.dirname(file.path));
        if (f == null) return null;
        if (!_imageExts.contains(p.extension(f.path).toLowerCase())) {
          issues.add(ImportIssue(
            source: rel,
            severity: ImportIssueSeverity.info,
            message: 'allegato non supportato (v1 solo immagini): $src',
          ));
          return null;
        }
        try {
          final bytes = f.readAsBytesSync();
          final hash = sha1.convert(bytes).toString();
          var key = assetKeyByHash[hash];
          if (key == null) {
            key = '${_uuid.v4()}_${p.basename(f.path)}';
            assetKeyByHash[hash] = key;
            assets[key] = bytes;
          }
          final decoder = img.findDecoderForData(bytes);
          final info = decoder?.startDecode(bytes);
          if (info == null) return null;
          return ImageBlock(assetKey: key, pxW: info.width, pxH: info.height);
        } catch (e) {
          issues.add(ImportIssue(source: rel, message: 'immagine: $e'));
          return null;
        }
      }

      final parser = MarkdownParser(
        resolveImage: resolveImage,
        onIssue: issues.add,
        sourceName: rel,
      );
      chapters.add(ImportedChapterDraft(
        title: title,
        blocks: parser.parse(markdown),
      ));
      // Yield so the progress dialog stays responsive on big vaults.
      await Future<void>.delayed(Duration.zero);
    }

    if (chapters.length > 200) {
      issues.add(ImportIssue(
        source: p.basename(vaultPath),
        message:
            '${chapters.length} capitoli: valuta di importare le sottocartelle separatamente',
      ));
    }

    return ImportedNotebookDraft(
      title: p.basename(vaultPath),
      tags: tags.toList()..sort(),
      chapters: chapters,
      assets: assets,
      issues: issues,
    );
  }

  /// Convert Obsidian wiki syntax to standard Markdown: `![[x]]` becomes an
  /// image (or is dropped with an issue for non-images), `[[Note|alias]]`
  /// becomes an internal link the parser styles as a blue span.
  String _rewriteWikiSyntax(
      String body, String source, List<ImportIssue> issues) {
    var out = body.replaceAllMapped(_embedPattern, (m) {
      final target = m.group(1)!.split('|').first.split('#').first.trim();
      if (_imageExts.contains(p.extension(target).toLowerCase())) {
        return '![](${Uri.encodeFull(target)})';
      }
      issues.add(ImportIssue(
        source: source,
        severity: ImportIssueSeverity.info,
        message: 'embed non importato (v1 solo immagini): $target',
      ));
      return '';
    });
    out = out.replaceAllMapped(_wikilinkPattern, (m) {
      final inner = m.group(1)!;
      final parts = inner.split('|');
      final target = parts.first.split('#').first.trim();
      final alias = (parts.length > 1 ? parts.last : parts.first).trim();
      return '[$alias]($kInternalLinkScheme${Uri.encodeFull(target)})';
    });
    return out;
  }
}
