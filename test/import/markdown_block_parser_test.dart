import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/markdown_block_parser.dart';

void main() {
  List<ImportBlock> parse(String src, {ImageBlockResolver? resolveImage}) =>
      MarkdownParser(resolveImage: resolveImage).parse(src);

  void expectSpanInvariant(TextBlock b) {
    expect(b.spans.map((s) => s.text).join(), b.plain,
        reason: 'concat(spans) deve essere uguale a plain');
  }

  test('headings map to levels with span invariant', () {
    final blocks = parse('# Uno\n\n## Due\n\n###### Sei');
    expect(blocks, hasLength(3));
    expect((blocks[0] as TextBlock).kind, BlockKind.heading1);
    expect((blocks[1] as TextBlock).kind, BlockKind.heading2);
    expect((blocks[2] as TextBlock).kind, BlockKind.heading6);
    for (final b in blocks) {
      expectSpanInvariant(b as TextBlock);
    }
  });

  test('inline styles produce styled spans', () {
    final blocks = parse('testo **grasso** e *corsivo* e ~~barrato~~ e `cod`');
    final b = blocks.single as TextBlock;
    expectSpanInvariant(b);
    expect(b.spans.any((s) => s.bold && s.text == 'grasso'), isTrue);
    expect(b.spans.any((s) => s.italic && s.text == 'corsivo'), isTrue);
    expect(b.spans.any((s) => s.strikethrough && s.text == 'barrato'), isTrue);
    expect(
        b.spans.any((s) => s.fontFamily == 'monospace' && s.text == 'cod'),
        isTrue);
  });

  test('external links keep visible text and append url', () {
    final blocks = parse('vedi [docs](https://example.com) qui');
    final b = blocks.single as TextBlock;
    expectSpanInvariant(b);
    expect(b.plain, contains('docs (https://example.com)'));
  });

  test('internal links become colored spans without url suffix', () {
    final blocks =
        parse('vedi [Nota](${kInternalLinkScheme}Nota) qui');
    final b = blocks.single as TextBlock;
    expectSpanInvariant(b);
    expect(b.plain, 'vedi Nota qui');
    expect(b.spans.any((s) => s.color == kLinkColor && s.text == 'Nota'),
        isTrue);
  });

  test('nested lists carry indent and prefixes', () {
    final blocks = parse('- uno\n- due\n  1. sub\n- [x] fatto\n- [ ] dafare');
    final texts = blocks.cast<TextBlock>();
    expect(texts[0].plain, '•  uno');
    expect(texts[0].kind, BlockKind.bullet);
    expect(texts[2].plain, '1.  sub');
    expect(texts[2].indentLevel, 1);
    expect(texts[3].plain, '☑  fatto');
    expect(texts[4].plain, '☐  dafare');
    for (final b in texts) {
      expectSpanInvariant(b);
    }
  });

  test('fenced code becomes monospace block', () {
    final blocks = parse('```\nvoid main() {}\nx = 1;\n```');
    final b = blocks.single as TextBlock;
    expect(b.kind, BlockKind.code);
    expect(b.plain, 'void main() {}\nx = 1;');
    expect(b.spans.single.fontFamily, 'monospace');
  });

  test('hr and table', () {
    final blocks = parse('---\n\n| a | b |\n|---|---|\n| 1 | 2 |');
    expect(blocks[0], isA<DividerBlock>());
    final t = blocks[1] as TableBlock;
    expect(t.rows, [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('display math extracted as MathBlock', () {
    final blocks = parse('prima\n\n\$\$\nE = mc^2\n\$\$\n\ndopo');
    expect(blocks.whereType<MathBlock>().single.latex, r'E = mc^2');
    expect(blocks.whereType<TextBlock>().map((b) => b.plain),
        containsAll(['prima', 'dopo']));
  });

  test('images resolved via callback, missing image keeps alt + issue', () {
    final issues = <ImportIssue>[];
    final parser = MarkdownParser(
      resolveImage: (src, alt) => src == 'ok.png'
          ? const ImageBlock(assetKey: 'k_ok.png', pxW: 100, pxH: 50)
          : null,
      onIssue: issues.add,
      sourceName: 'test.md',
    );
    final blocks = parser.parse('![c](ok.png)\n\n![alt2](missing.png)');
    expect(blocks.whereType<ImageBlock>().single.assetKey, 'k_ok.png');
    expect(blocks.whereType<TextBlock>().single.plain, '[alt2]');
    expect(issues.single.message, contains('missing.png'));
  });

  test('adjacent same-style spans are merged', () {
    final blocks = parse('a b c normale');
    final b = blocks.single as TextBlock;
    expect(b.spans, hasLength(1));
  });
}
