import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/import/data/block_paginator.dart';
import 'package:abelnotes/features/import/data/frontmatter.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/notion_importer.dart';
import 'package:abelnotes/features/import/data/obsidian_importer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:image/image.dart' as img;

Uint8List tinyPng() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 4)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frontmatter', () {
    test('tags list and string forms, hash stripped', () {
      expect(
          stripFrontmatter('---\ntags:\n  - uni\n  - "#lab"\n---\ncorpo')
              .tags,
          ['uni', 'lab']);
      expect(stripFrontmatter('---\ntags: a, b c\n---\nx').tags,
          ['a', 'b', 'c']);
      final r = stripFrontmatter('---\ntags: [x]\n---\ncorpo qui');
      expect(r.body, 'corpo qui');
    });

    test('no frontmatter or malformed yaml is harmless', () {
      expect(stripFrontmatter('# solo testo').body, '# solo testo');
      expect(stripFrontmatter('---\n: : :\n---\nok').body, 'ok');
    });
  });

  group('ObsidianImporter', () {
    late Directory vault;

    setUp(() async {
      vault = await Directory.systemTemp.createTemp('vault_test_');
      File('${vault.path}/.obsidian/app.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('${vault.path}/Nota.md').writeAsStringSync(
          '---\ntags: [scuola]\n---\n# Titolo\n\nvedi [[Altra|alias]] e ![[foto.png]]');
      File('${vault.path}/sub/Altra.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('contenuto');
      File('${vault.path}/allegati/foto.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(tinyPng());
    });

    tearDown(() => vault.delete(recursive: true));

    test('vault becomes draft: chapters, tags, wikilinks, embeds', () async {
      final draft = await ObsidianImporter().parse(vault.path);
      expect(draft.chapters, hasLength(2));
      expect(draft.chapters.map((c) => c.title),
          containsAll(['Nota', 'sub / Altra']));
      expect(draft.tags, ['scuola']);
      final nota =
          draft.chapters.firstWhere((c) => c.title == 'Nota').blocks;
      // Wikilink alias becomes a blue span, embed resolves by basename.
      final linkPara = nota.whereType<TextBlock>().firstWhere(
          (b) => b.plain.contains('alias'));
      expect(linkPara.spans.any((s) => s.text == 'alias' && s.color != null),
          isTrue);
      expect(nota.whereType<ImageBlock>(), hasLength(1));
      expect(draft.assets, hasLength(1));
    });

    test('hidden dirs skipped, empty vault throws', () async {
      final empty = await Directory.systemTemp.createTemp('vuoto_');
      addTearDown(() => empty.delete(recursive: true));
      expect(() => ObsidianImporter().parse(empty.path),
          throwsFormatException);
    });
  });

  group('NotionImporter', () {
    Uint8List makeNotionZip() {
      const id = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
      final archive = Archive();
      void add(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
      add('Export/Pagina $id.md',
          utf8.encode('# Ciao\n\n![img](Pagina%20$id/img.png)\n\nvedi [Sub](Sub%20$id.md)'));
      add('Export/Pagina $id/img.png', tinyPng());
      add('Export/Sub $id.md', utf8.encode('sotto pagina'));
      add('Export/Db $id.csv', utf8.encode('nome,valore\r\na,"1,5"\r\n'));
      add('Export/Db ${id}_all.csv',
          utf8.encode('nome,valore\r\na,"1,5"\r\nb,2\r\n'));
      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    }

    test('detection, id stripping, links, csv preference', () async {
      final zip = makeNotionZip();
      expect(
          NotionImporter.looksLikeNotionExport(
              ZipDecoder().decodeBytes(zip)),
          isTrue);
      final draft =
          await NotionImporter().parse(zip, exportName: 'Export.zip');
      expect(draft.title, 'Export');
      expect(draft.chapters.map((c) => c.title),
          containsAll(['Export / Pagina', 'Export / Sub', 'Export / Db']));
      // Only the _all.csv variant becomes a chapter.
      expect(
          draft.chapters.where((c) => c.title.contains('Db')), hasLength(1));
      final db = draft.chapters.firstWhere((c) => c.title.contains('Db'));
      final table = db.blocks.single as TableBlock;
      expect(table.rows, hasLength(3)); // header + 2 rows (quoted comma ok)
      expect(table.rows[1], ['a', '1,5']);
      // Image resolved from URL-encoded path; internal link has no url suffix.
      final pagina =
          draft.chapters.firstWhere((c) => c.title == 'Export / Pagina');
      expect(pagina.blocks.whereType<ImageBlock>(), hasLength(1));
      final linkBlock = pagina.blocks
          .whereType<TextBlock>()
          .firstWhere((b) => b.plain.contains('Sub'));
      expect(linkBlock.plain, isNot(contains('.md')));
    });

    test('non-notion zip fails cleanly', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 4, utf8.encode('ciao')));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(() => NotionImporter().parse(zip, exportName: 'x.zip'),
          throwsFormatException);
    });
  });

  test('round-trip: obsidian draft → pages → PageData json → parse back',
      () async {
    final vault = await Directory.systemTemp.createTemp('vault_rt_');
    addTearDown(() => vault.delete(recursive: true));
    File('${vault.path}/N.md').writeAsStringSync(
        '# T\n\nparagrafo **ricco**\n\n- a\n- b\n\n```\ncode\n```');
    final draft = await ObsidianImporter().parse(vault.path);
    final pages = await BlockPaginator().paginate(draft.chapters.single.blocks);
    for (final page in pages) {
      final pd = PageData(
        pageId: 'p1',
        pageNumber: 1,
        width: BlockPaginator.pageW,
        height: BlockPaginator.pageH,
        layers: RenderingLayers(
          background: const BackgroundLayer(type: 'blank'),
          content: page.elements,
        ),
        assetReferences: page.assetRefs.toList(),
      );
      final decoded =
          PageData.fromJson(jsonDecode(jsonEncode(pd.toJson())));
      expect(decoded.layers.content.length, page.elements.length);
    }
  });
}
