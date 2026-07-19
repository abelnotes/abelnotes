import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/import/data/block_paginator.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

TextBlock para(String text, {BlockKind kind = BlockKind.paragraph}) =>
    TextBlock(
      spans: [TextSpanData(text: text)],
      plain: text,
      kind: kind,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('short content stays on one page inside margins', () async {
    final pages = await BlockPaginator()
        .paginate([para('ciao'), para('mondo'), const DividerBlock()]);
    expect(pages, hasLength(1));
    for (final el in pages.single.elements) {
      el.maybeMap(
        text: (t) {
          expect(t.data.y, greaterThanOrEqualTo(BlockPaginator.topY));
          expect(t.data.y + t.data.height,
              lessThanOrEqualTo(BlockPaginator.bottomY));
        },
        orElse: () {},
      );
    }
  });

  test('many paragraphs flow onto multiple pages, none past bottom margin',
      () async {
    final blocks = [for (var i = 0; i < 120; i++) para('paragrafo numero $i')];
    final pages = await BlockPaginator().paginate(blocks);
    expect(pages.length, greaterThan(1));
    var placed = 0;
    for (final page in pages) {
      for (final el in page.elements) {
        el.maybeMap(
          text: (t) {
            placed++;
            expect(t.data.y + t.data.height,
                lessThanOrEqualTo(BlockPaginator.bottomY + 0.01),
                reason: 'elemento oltre il margine inferiore');
          },
          orElse: () {},
        );
      }
    }
    expect(placed, blocks.length);
  });

  test('over-tall block splits across pages preserving span invariant',
      () async {
    final giant = List.generate(400, (i) => 'riga $i').join('\n');
    final pages = await BlockPaginator().paginate([para(giant)]);
    expect(pages.length, greaterThan(1));
    final fragments = <String>[];
    for (final page in pages) {
      for (final el in page.elements) {
        el.maybeMap(
          text: (t) {
            expect(t.data.spans.map((s) => s.text).join(), t.data.content);
            fragments.add(t.data.content);
          },
          orElse: () {},
        );
      }
    }
    // No content lost: all original lines survive across the fragments.
    final rejoined = fragments.join('\n');
    expect(rejoined.split('\n').where((l) => l.isNotEmpty).length, 400);
  });

  test('orphan heading moves to the next page with its content', () async {
    // Fill the page almost completely, then a heading + paragraph.
    final filler = List.generate(43, (i) => 'x').join('\n');
    final pages = await BlockPaginator().paginate([
      para(filler),
      para('Titolo', kind: BlockKind.heading2),
      para('contenuto sotto il titolo'),
    ]);
    if (pages.length > 1) {
      // Wherever the paragraph landed, the heading must be on the same page.
      final headingPage = pages.indexWhere((p) => p.elements.any((e) =>
          e.maybeMap(text: (t) => t.data.content == 'Titolo', orElse: () => false)));
      final paraPage = pages.indexWhere((p) => p.elements.any((e) => e.maybeMap(
          text: (t) => t.data.content == 'contenuto sotto il titolo',
          orElse: () => false)));
      expect(headingPage, paraPage);
    }
  });

  test('image scales to fit and registers asset reference', () async {
    final pages = await BlockPaginator().paginate([
      const ImageBlock(assetKey: 'k_img.png', pxW: 4000, pxH: 1000),
    ]);
    final img = pages.single.elements.single.maybeMap(
        image: (i) => i.data, orElse: () => null)!;
    expect(img.width, lessThanOrEqualTo(BlockPaginator.contentW));
    expect(img.width / img.height, closeTo(4.0, 0.01));
    expect(pages.single.assetRefs, contains('k_img.png'));
  });

  test('code block gets a background card behind the text', () async {
    final pages = await BlockPaginator()
        .paginate([para('int x = 1;', kind: BlockKind.code)]);
    final els = pages.single.elements;
    expect(els, hasLength(2));
    final shape =
        els.first.maybeMap(shape: (s) => s.data, orElse: () => null);
    expect(shape, isNotNull, reason: 'card di sfondo assente o sopra il testo');
    expect(shape!.fillColor, isNotNull);
    expect(els.first.zIndex, lessThan(els.last.zIndex));
  });

  test('table becomes monospace grid text', () async {
    final pages = await BlockPaginator().paginate([
      const TableBlock(rows: [
        ['nome', 'valore'],
        ['a', '1'],
      ]),
    ]);
    final t = pages.single.elements.last
        .maybeMap(text: (t) => t.data, orElse: () => null)!;
    expect(t.fontFamily, 'monospace');
    expect(t.content, contains('nome'));
    expect(t.content, contains('─'));
  });
}
