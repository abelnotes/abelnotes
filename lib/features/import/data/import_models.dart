import 'dart:typed_data';

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Intermediate representation shared by every foreign-format importer
/// (Obsidian, Notion, later GoodNotes/OneNote). Format adapters run in a
/// background isolate and emit these plain-data drafts; the paginator turns
/// them into ncnote [PageData] on the main isolate.

/// Kind of a text block — drives base styling and spacing in the paginator.
enum BlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  bullet,
  ordered,
  task,
  quote,
  code,
}

sealed class ImportBlock {
  const ImportBlock();
}

/// One paragraph / heading / list item / quote line / code block.
class TextBlock extends ImportBlock {
  /// Rich runs. Invariant: concat(spans.text) == [plain] — the same
  /// invariant the canvas [TextData] model requires.
  final List<TextSpanData> spans;
  final String plain;
  final BlockKind kind;

  /// List nesting depth (0 = top level). Indents the element by
  /// 20pt per level at pagination time.
  final int indentLevel;

  const TextBlock({
    required this.spans,
    required this.plain,
    this.kind = BlockKind.paragraph,
    this.indentLevel = 0,
  });
}

/// An image whose bytes live in [ImportedNotebookDraft.assets] under
/// [assetKey]. [pxW]/[pxH] are the intrinsic pixel dimensions (probed from
/// the header at parse time) used to compute layout size.
class ImageBlock extends ImportBlock {
  final String assetKey;
  final int pxW;
  final int pxH;

  const ImageBlock({
    required this.assetKey,
    required this.pxW,
    required this.pxH,
  });
}

/// Horizontal rule.
class DividerBlock extends ImportBlock {
  const DividerBlock();
}

/// A table, rendered v1 as a column-padded monospace grid.
class TableBlock extends ImportBlock {
  final List<List<String>> rows;

  const TableBlock({required this.rows});
}

/// A display math block (`$$…$$`) — becomes a native MathElement.
class MathBlock extends ImportBlock {
  final String latex;

  const MathBlock({required this.latex});
}

/// One chapter of the future notebook (for Markdown sources: one .md file).
class ImportedChapterDraft {
  final String title;
  final List<ImportBlock> blocks;

  const ImportedChapterDraft({required this.title, required this.blocks});
}

/// A complete parsed source, ready for pagination. Plain data only so it
/// can cross the isolate boundary.
class ImportedNotebookDraft {
  final String title;
  final List<String> tags;
  final List<ImportedChapterDraft> chapters;

  /// Raw asset bytes keyed by their future `assets/<key>` name.
  final Map<String, Uint8List> assets;
  final List<ImportIssue> issues;

  const ImportedNotebookDraft({
    required this.title,
    this.tags = const [],
    required this.chapters,
    this.assets = const {},
    this.issues = const [],
  });
}

enum ImportIssueSeverity { info, warning, error }

/// One per-file problem surfaced to the user in the final report
/// ("image X not found", "page skipped"). Never fails the whole import
/// unless severity is [ImportIssueSeverity.error] at the source level.
class ImportIssue {
  final String source;
  final ImportIssueSeverity severity;
  final String message;

  const ImportIssue({
    required this.source,
    this.severity = ImportIssueSeverity.warning,
    required this.message,
  });
}

enum ImportPhase { scanning, parsing, paginating, packaging, done }

/// Streaming progress for the import dialog.
class ImportProgress {
  final ImportPhase phase;
  final int current;
  final int total;

  /// Currently processed file/chapter name, for the dialog subtitle.
  final String? detail;

  const ImportProgress({
    required this.phase,
    this.current = 0,
    this.total = 0,
    this.detail,
  });
}

/// Final outcome shown in the report dialog.
class ImportReport {
  final String notebookTitle;
  final String notebookId;
  final int chapterCount;
  final int pageCount;
  final List<ImportIssue> issues;

  const ImportReport({
    required this.notebookTitle,
    required this.notebookId,
    required this.chapterCount,
    required this.pageCount,
    this.issues = const [],
  });
}

/// Source types the detector can recognise.
enum ImportSourceType { ncnote, obsidianVault, notionExport, goodnotes, onenote }
