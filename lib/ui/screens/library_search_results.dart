import 'package:flutter/material.dart';

import 'package:abelnotes/core/providers/notebook_provider.dart'
    show NotebookEntry;
import 'package:abelnotes/core/services/search_service.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart'
    show CoverPatternPainter, CoverStyle;
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// "In your notes": what the library search found inside notebooks.
class LibrarySearchResults extends StatefulWidget {
  final List<SearchHit> hits;
  final bool indexing;
  final double hPad;
  final double topGap;
  final Map<String, NotebookEntry> notebooks;
  final ValueChanged<SearchHit> onOpen;

  const LibrarySearchResults({
    super.key,
    required this.hits,
    required this.indexing,
    required this.hPad,
    this.topGap = 28,
    required this.notebooks,
    required this.onOpen,
  });

  /// Rows shown before "Show N more".
  static const firstRows = 50;

  @override
  State<LibrarySearchResults> createState() => _LibrarySearchResultsState();
}

class _LibrarySearchResultsState extends State<LibrarySearchResults> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final hits = widget.hits;
    final shown = _all || hits.length <= LibrarySearchResults.firstRows
        ? hits
        : hits.sublist(0, LibrarySearchResults.firstRows);
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.hPad, widget.topGap, widget.hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rows carry 8 of their own padding; the heading lines up with them.
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(l10n.srchSection,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HwType.title.copyWith(color: p.ink0, fontSize: 17)),
          ),
          if (widget.indexing)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text(l10n.srchIndexing,
                  style: TextStyle(fontSize: 12, color: p.ink2)),
            ),
          const SizedBox(height: 10),
          for (final h in shown)
            _HitRow(
                hit: h,
                entry: widget.notebooks[h.notebookId],
                onTap: () => widget.onOpen(h)),
          if (shown.length < hits.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                onPressed: () => setState(() => _all = true),
                child: Text(l10n.srchShowMore(hits.length - shown.length)),
              ),
            ),
        ],
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final SearchHit hit;
  final NotebookEntry? entry;
  final VoidCallback onTap;
  const _HitRow({required this.hit, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final cover = entry == null ? p.paper3 : Color(entry!.metadata.coverColor);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 32,
                decoration: BoxDecoration(
                  color: cover,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: hwShadow1(p.brightness),
                ),
                clipBehavior: Clip.antiAlias,
                child: entry == null
                    ? null
                    : CustomPaint(
                        painter: CoverPatternPainter(
                            CoverStyle.fromKey(entry!.metadata.coverStyle))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: hit.notebookTitle,
                            style: TextStyle(
                                fontWeight: FontWeight.w600, color: p.ink0)),
                        TextSpan(
                            text: '  ·  ${l10n.srchPageN(hit.pageNumber)}',
                            style: TextStyle(color: p.ink2, fontSize: 12)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      _highlighted(hit, p),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, height: 1.35, color: p.ink1),
                    ),
                  ],
                ),
              ),
              if (entry?.notOnDevice ?? false) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: HwIcon('cloud-download', size: 14, color: p.ink2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static TextSpan _highlighted(SearchHit h, HwPalette p) {
    final s = h.snippet;
    final spans = <TextSpan>[];
    var at = 0;
    for (final (a, b) in h.ranges) {
      final from = a.clamp(0, s.length), to = b.clamp(0, s.length);
      if (to <= from || from < at) continue;
      if (from > at) spans.add(TextSpan(text: s.substring(at, from)));
      spans.add(TextSpan(
          text: s.substring(from, to),
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: p.accentDeep,
              backgroundColor: p.accentSoft)));
      at = to;
    }
    if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
    return TextSpan(children: spans);
  }
}
