// ═══════════════════════════════════════════════════════════════
//  page_grid.dart
//
//  Thumbnail grid of the page manager: browse and reorder, select, or place
//  the tray's pages (a dashed slot shows where they land).
// ═══════════════════════════════════════════════════════════════

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/thumbnail_simplify.dart';
import 'package:abelnotes/features/canvas/presentation/preview_rasters.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/features/pages_tray/presentation/tray_widgets.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_motion.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

enum PageGridMode { browse, select, place }

const double _kMaxTileExtent = 260;
const double _kSpacing = 14;
const double _kAspect = 0.60;
const double _kHPad = 16;

/// Scroll offset that brings grid row [row] to the top of a viewport of
/// [width] (the grid's own cross-axis metrics).
double gridRowOffset(double width, int row) {
  final inner = width - _kHPad * 2;
  final count = max(1, (inner / (_kMaxTileExtent + _kSpacing)).ceil());
  final tileW = (inner - _kSpacing * (count - 1)) / count;
  return row * (tileW / _kAspect + _kSpacing);
}

int gridColumns(double width) {
  final inner = width - _kHPad * 2;
  return max(1, (inner / (_kMaxTileExtent + _kSpacing)).ceil());
}

class PageGrid extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final CanvasState liveState;
  final List<int> visibleIndices;
  final PageGridMode mode;
  final Set<String> selectedIds;
  final Set<String> movingIds;
  final Set<String> landingIds;
  final int landingStamp;

  /// Tray whose slot is shown in [PageGridMode.place], and where.
  final PagesTray? tray;
  final PasteSlot? slot;
  final String ghostLabel;
  final double topPadding;
  final double bottomPadding;
  final Widget? hint;

  final void Function(int docIndex) onTapPage;
  final void Function(int docIndex, String action) onPageAction;
  final void Function(int docIndex) onToggleSelect;
  final void Function(int docIndex, List<int> visible) onRangeSelect;
  final void Function(int docIndex) onLongPressToSelect;
  final void Function(int docIndex, bool before) onPickSlot;
  final VoidCallback onConfirmGhost;

  const PageGrid({
    super.key,
    required this.scrollController,
    required this.liveState,
    required this.visibleIndices,
    required this.mode,
    required this.selectedIds,
    required this.movingIds,
    required this.landingIds,
    required this.landingStamp,
    required this.tray,
    required this.slot,
    required this.ghostLabel,
    required this.topPadding,
    required this.bottomPadding,
    required this.hint,
    required this.onTapPage,
    required this.onPageAction,
    required this.onToggleSelect,
    required this.onRangeSelect,
    required this.onLongPressToSelect,
    required this.onPickSlot,
    required this.onConfirmGhost,
  });

  @override
  ConsumerState<PageGrid> createState() => _PageGridState();
}

class _PageGridState extends ConsumerState<PageGrid> {
  bool _didInitialScroll = false;
  int _scrolledLandingStamp = 0;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(PageGrid old) {
    super.didUpdateWidget(old);
    if (widget.landingStamp != 0 &&
        widget.landingStamp != _scrolledLandingStamp &&
        widget.landingIds.isNotEmpty) {
      _scrolledLandingStamp = widget.landingStamp;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLanding());
    }
  }

  void _scrollTo(int docIdx, {bool animate = false}) {
    final c = widget.scrollController;
    if (!c.hasClients || _width == 0) return;
    final vis = widget.visibleIndices.indexOf(docIdx);
    if (vis < 0) return;
    final row = vis ~/ gridColumns(_width);
    final viewport = c.position.viewportDimension;
    final target = (widget.topPadding + gridRowOffset(_width, row) - viewport / 3)
        .clamp(0.0, c.position.maxScrollExtent)
        .toDouble();
    if (animate && !hwReduceMotion(context)) {
      c.animateTo(target,
          duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    } else {
      c.jumpTo(target);
    }
  }

  void _scrollToCurrent() {
    if (_didInitialScroll || !mounted) return;
    _didInitialScroll = true;
    _scrollTo(widget.liveState.currentPageIndex);
  }

  void _scrollToLanding() {
    if (!mounted) return;
    final ids = widget.landingIds;
    final i = widget.liveState.document.pages
        .indexWhere((e) => ids.contains(e.pageId));
    if (i >= 0) _scrollTo(i, animate: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.liveState;
    final vis = widget.visibleIndices;
    // Where the dashed slot goes: before the first visible page that follows
    // the page the tray lands after.
    int? ghostAt;
    if (widget.mode == PageGridMode.place && widget.tray != null) {
      final afterId = widget.tray!.isMove
          ? skipMoving(s.document, widget.slot?.afterPageId, widget.movingIds)
          : widget.slot?.afterPageId;
      final afterIdx = afterId == null
          ? -1
          : s.document.pages.indexWhere((e) => e.pageId == afterId);
      ghostAt = vis.length;
      for (var i = 0; i < vis.length; i++) {
        if (vis[i] > afterIdx) {
          ghostAt = i;
          break;
        }
      }
    }
    final total = vis.length + (ghostAt == null ? 0 : 1);
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth;
      return CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: widget.topPadding)),
          if (widget.hint != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(_kHPad, 0, _kHPad, 12),
              sliver: SliverToBoxAdapter(child: widget.hint),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: _kHPad),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _kMaxTileExtent,
                childAspectRatio: _kAspect,
                crossAxisSpacing: _kSpacing,
                mainAxisSpacing: _kSpacing,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  if (ghostAt != null && i == ghostAt) return _ghost(ctx);
                  final visIdx = ghostAt != null && i > ghostAt ? i - 1 : i;
                  return _tileAt(ctx, visIdx);
                },
                childCount: total,
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: widget.bottomPadding)),
        ],
      );
    });
  }

  // ── ghost slot ──

  Widget _ghost(BuildContext ctx) {
    final p = HwThemeScope.of(ctx);
    final tray = widget.tray!;
    return Semantics(
      button: true,
      label: widget.ghostLabel,
      child: GestureDetector(
        key: const ValueKey('ghost-slot'),
        onTap: widget.onConfirmGhost,
        child: Column(children: [
          Expanded(
            child: CustomPaint(
              foregroundPainter: _DashedRRectPainter(p.accent, 5, 2),
              child: Container(
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                alignment: Alignment.center,
                child: Transform.scale(scale: 1.25, child: TrayFan(tray: tray)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.ghostLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: p.accentDeep)),
        ]),
      ),
    );
  }

  // ── tiles ──

  Widget _tileAt(BuildContext ctx, int visIdx) {
    final s = widget.liveState;
    final index = widget.visibleIndices[visIdx];
    if (index >= s.document.pages.length) return const SizedBox.shrink();
    final entry = s.document.pages[index];
    final page = s.pages[entry.fileName];
    final isCurrent = index == s.currentPageIndex;
    final selecting = widget.mode == PageGridMode.select;
    final selected = selecting && widget.selectedIds.contains(entry.pageId);
    final moving = widget.movingIds.contains(entry.pageId);
    final landing = widget.landingIds.contains(entry.pageId);

    final tile = _PageTile(
      key: ValueKey('${entry.pageId}-${landing ? widget.landingStamp : 0}'),
      thumb: _thumbnail(index, page, s),
      number: index + 1,
      chapterColor: _chapterColor(s, entry.chapterId),
      isCurrent: isCurrent && widget.mode == PageGridMode.browse,
      selecting: selecting,
      selected: selected,
      moving: moving,
      landing: landing,
      menu: widget.mode == PageGridMode.browse ? _menu(ctx, index, visIdx) : null,
    );

    switch (widget.mode) {
      case PageGridMode.select:
        return KeyedSubtree(
          key: ValueKey(entry.pageId),
          child: GestureDetector(
            onTap: () {
              if (HardwareKeyboard.instance.isShiftPressed) {
                widget.onRangeSelect(index, widget.visibleIndices);
              } else {
                widget.onToggleSelect(index);
              }
            },
            child: tile,
          ),
        );
      case PageGridMode.place:
        return KeyedSubtree(
          key: ValueKey(entry.pageId),
          child: _PlaceTarget(
            onPick: (before) => widget.onPickSlot(index, before),
            child: tile,
          ),
        );
      case PageGridMode.browse:
        // Long press starts a selection; moving pages goes through Move.
        return KeyedSubtree(
          key: ValueKey(entry.pageId),
          child: GestureDetector(
            onTap: () {
              if (HardwareKeyboard.instance.isShiftPressed) {
                widget.onRangeSelect(index, widget.visibleIndices);
              } else {
                widget.onTapPage(index);
              }
            },
            onLongPress: () {
              HapticFeedback.lightImpact();
              widget.onLongPressToSelect(index);
            },
            child: tile,
          ),
        );
    }
  }

  Color? _chapterColor(CanvasState s, String? chapterId) {
    final i = s.metadata.chapters.indexWhere((c) => c.id == chapterId);
    return i < 0 ? null : kChapterDots[i % kChapterDots.length];
  }

  Widget _menu(BuildContext ctx, int index, int visIdx) {
    final p = HwThemeScope.of(ctx);
    final l = AppLocalizations.of(ctx);
    final s = widget.liveState;
    Widget row(String icon, String label, {Color? color}) {
      final c = color ?? p.ink0;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        HwIcon(icon, size: 16, color: c),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: c)),
      ]);
    }

    return PopupMenuButton<String>(
      icon: HwIcon('more', size: 18, color: p.ink2),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'copy', child: row('copy', l.pgtCopy)),
        PopupMenuItem(value: 'move', child: row('move', l.pgtMove)),
        PopupMenuItem(
            value: 'insert_before', child: row('plus', l.pmInsertBefore)),
        PopupMenuItem(
            value: 'insert_after', child: row('plus', l.pmInsertAfter)),
        PopupMenuItem(
            value: 'duplicate', child: row('duplicate', l.pmDuplicate)),
        if (s.pageCount > 1)
          PopupMenuItem(value: 'moveto', child: row('sort', l.pmMoveTo)),
        PopupMenuItem(
            value: 'chapter', child: row('chapter', l.pmChapterEllipsis)),
        if (s.pageCount > 1)
          PopupMenuItem(
            value: 'delete',
            child: row('trash', l.pmDelete, color: HwTheme.syncConflict),
          ),
      ],
      onSelected: (action) => widget.onPageAction(index, action),
    );
  }

  CanvasRenderEngine _previewEngine(PageData page, CanvasState state,
          Set<String> corruptAssetIds, {bool fast = false}) =>
      CanvasRenderEngine(
        pageData: page,
        zoom: 1.0,
        panOffset: Offset.zero,
        imageCache: state.imageCache,
        corruptAssetIds: corruptAssetIds,
        previewStrokes: fast,
      );

  /// The preview's ink: on the web a bitmap made once (see PreviewRasters),
  /// elsewhere the vector drawing.
  Widget _previewInk(BuildContext ctx, Size size, PageData page,
      CanvasState state, Set<String> corruptAssetIds, bool loading) {
    final dpr = MediaQuery.devicePixelRatioOf(ctx);
    final pw = (size.width * dpr).round(), ph = (size.height * dpr).round();
    PageData simplified() => simplifyForPreview(
        page, min(size.width / page.width, size.height / page.height) * dpr);
    Widget vector() => CustomPaint(
          painter: _previewEngine(simplified(), state, corruptAssetIds),
          size: Size.infinite,
        );
    // A preview whose images are still decoding would be kept without them.
    if (!kIsWeb || loading || pw <= 0 || ph <= 0 || pw * ph > 4000000) {
      return vector();
    }
    final rasters = PreviewRasters.instance;
    final key = PreviewKey(page, pw, ph, state.imageCache);
    return ValueListenableBuilder<int>(
      valueListenable: rasters.version,
      builder: (_, __, ___) {
        final img = rasters.lookup(key);
        if (img != null) {
          return RawImage(
              image: img, fit: BoxFit.fill, filterQuality: FilterQuality.low);
        }
        if (rasters.failed(key)) return vector();
        rasters.request(key, () {
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec)..scale(dpr);
          _previewEngine(simplified(), state, corruptAssetIds, fast: true)
              .paint(canvas, size);
          final pic = rec.endRecording();
          try {
            return pic.toImageSync(pw, ph);
          } finally {
            pic.dispose();
          }
        });
        return const SizedBox.expand();
      },
    );
  }

  // ── thumbnail (lazy asset decoding, corrupt/loading badges) ──

  Widget _thumbnail(int docIndex, PageData? page, CanvasState state) {
    if (page != null) {
      bool hasMissing = false;
      for (final el in page.layers.content) {
        if (el is ImageElement &&
            !state.imageCache.containsKey(el.data.assetPath)) {
          hasMissing = true;
          break;
        }
      }
      if (hasMissing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final notifier = ref.read(canvasProvider.notifier);
          for (final el in page.layers.content) {
            if (el is ImageElement) {
              notifier.ensureAssetDecodedForThumbnail(el.data.assetPath);
            }
          }
        });
      }
    }
    bool hasCorruptAsset = false;
    bool hasLoadingAsset = false;
    final notifier = ref.read(canvasProvider.notifier);
    final corruptAssetIds =
        page != null ? notifier.corruptAssetIds : const <String>{};
    final loadingAssetIds =
        page != null ? notifier.loadingAssetIds : const <String>{};
    if (page != null &&
        (corruptAssetIds.isNotEmpty || loadingAssetIds.isNotEmpty)) {
      for (final el in page.layers.content) {
        if (el is ImageElement) {
          final ap = el.data.assetPath;
          if (corruptAssetIds.contains(ap)) {
            hasCorruptAsset = true;
            break;
          }
          if (loadingAssetIds.contains(ap)) hasLoadingAsset = true;
        }
      }
    }
    return LayoutBuilder(builder: (ctx, constraints) {
      // Simplified only when drawn: on the web that happens between frames.
      final previewPage = page;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: previewPage != null
              ? Stack(fit: StackFit.expand, children: [
                  _previewInk(ctx, constraints.biggest, previewPage, state,
                      corruptAssetIds, hasLoadingAsset),
                  if (hasCorruptAsset)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Tooltip(
                        message: AppLocalizations.of(ctx).pmCorruptAssetTooltip,
                        child: const Icon(Icons.broken_image_rounded,
                            color: Color(0xFFE65100), size: 18),
                      ),
                    )
                  else if (hasLoadingAsset)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Tooltip(
                        message: AppLocalizations.of(ctx).pmLoadingImageTooltip,
                        child: const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Color(0xFF1976D2)),
                          ),
                        ),
                      ),
                    ),
                ])
              : Center(
                  child: Icon(Icons.description_outlined,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ),
      );
    });
  }
}

/// One page of the grid.
class _PageTile extends StatelessWidget {
  final Widget thumb;
  final int number;
  final Color? chapterColor;
  final bool isCurrent;
  final bool selecting;
  final bool selected;
  final bool moving;
  final bool landing;
  final Widget? menu;

  const _PageTile({
    super.key,
    required this.thumb,
    required this.number,
    required this.chapterColor,
    required this.isCurrent,
    required this.selecting,
    required this.selected,
    required this.moving,
    required this.landing,
    required this.menu,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l = AppLocalizations.of(context);
    final reduce = hwReduceMotion(context);
    Widget paper = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
              color: p.ink0.withValues(alpha: 0.10),
              blurRadius: 1,
              spreadRadius: 1),
          BoxShadow(
              color: p.ink0.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 6),
              spreadRadius: -6),
        ],
      ),
      child: thumb,
    );
    if (landing) {
      paper = _LandingFlash(reduce: reduce, color: p.accent, child: paper);
    }
    final ring = selected || isCurrent ? p.accent : null;
    final scale = selected ? 0.955 : 1.0;
    return Opacity(
      opacity: moving ? 0.5 : 1,
      child: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedScale(
                scale: scale,
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Container(
                  decoration: ring == null
                      ? null
                      : BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                              color: ring, width: selected ? 3 : 2.5)),
                  padding: ring == null ? null : const EdgeInsets.all(0),
                  child: paper,
                ),
              ),
            ),
            if (moving)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                      painter: _DashedRRectPainter(p.ink3, 4, 2)),
                ),
              ),
            if (moving)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(5, 3, 7, 3),
                  decoration: BoxDecoration(
                    color: p.paper0,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                          color: p.ink0.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    HwIcon('move', size: 12, color: p.ink0),
                    const SizedBox(width: 4),
                    Text(l.pgtTagMoving,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: p.ink0)),
                  ]),
                ),
              ),
            if (selecting)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? p.accent : Colors.black26,
                    border: Border.all(
                        color: selected ? p.accent : Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: selected
                      ? HwIcon('check', size: 14, color: p.onAccent)
                      : null,
                ),
              )
            else if (menu != null)
              Positioned(top: 2, right: 2, child: menu!),
          ]),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (chapterColor != null) ...[
              Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: chapterColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text('$number',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    color: isCurrent || selected ? p.accentDeep : p.ink2,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ]),
    );
  }
}

/// Springs in and flashes the accent colour once; static under reduced motion.
class _LandingFlash extends StatelessWidget {
  final bool reduce;
  final Color color;
  final Widget child;
  const _LandingFlash(
      {required this.reduce, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    if (reduce) {
      return Stack(fit: StackFit.expand, children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color, width: 3),
            ),
          ),
        ),
      ]);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1900),
      builder: (ctx, t, _) {
        final pop = Curves.easeOutBack.transform((t * 1900 / 650).clamp(0.0, 1.0));
        return Transform.scale(
          scale: 0.7 + 0.3 * pop,
          child: Opacity(
            opacity: pop.clamp(0.0, 1.0),
            child: Stack(fit: StackFit.expand, children: [
              child,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: color.withValues(alpha: 0.5 * (1 - t)),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Tap on the left third = before this page, anywhere else = after it; the
/// hovered edge shows a "+" marker.
class _PlaceTarget extends StatefulWidget {
  final Widget child;
  final void Function(bool before) onPick;
  const _PlaceTarget({required this.child, required this.onPick});

  @override
  State<_PlaceTarget> createState() => _PlaceTargetState();
}

class _PlaceTargetState extends State<_PlaceTarget> {
  int _hover = -1; // 0 = left edge, 1 = right edge

  bool _isLeft(Offset local, double width) => local.dx < width * 0.34;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      return MouseRegion(
        onHover: (e) {
          final h = _isLeft(e.localPosition, w) ? 0 : 1;
          if (h != _hover) setState(() => _hover = h);
        },
        onExit: (_) => setState(() => _hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onPick(_isLeft(d.localPosition, w)),
          child: Stack(clipBehavior: Clip.none, children: [
            widget.child,
            if (_hover >= 0)
              Positioned(
                top: -4,
                bottom: 26,
                left: _hover == 0 ? -9 : null,
                right: _hover == 1 ? -9 : null,
                width: 12,
                child: IgnorePointer(
                  child: Stack(alignment: Alignment.center, children: [
                    Container(
                        width: 3,
                        decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(2))),
                    Container(
                      width: 22,
                      height: 22,
                      decoration:
                          BoxDecoration(color: p.accent, shape: BoxShape.circle),
                      child: HwIcon('plus', size: 14, color: p.onAccent),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double width;
  _DashedRRectPainter(this.color, this.radius, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(width / 2), Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius || old.width != width;
}
