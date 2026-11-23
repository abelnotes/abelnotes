// ═══════════════════════════════════════════════════════════════
//  page_manager_sheet.dart
//
//  Page manager sheet: browse, reorder, select; Copy / Move / Duplicate /
//  Delete; and the pages tray's destination picker. The tray itself is in
//  lib/features/pages_tray (README there).
// ═══════════════════════════════════════════════════════════════

import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/shared/utils/text_controller_scope.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/page_grid.dart';
import 'package:abelnotes/features/pages_tray/application/pages_tray_provider.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/features/pages_tray/presentation/notebook_chooser.dart';
import 'package:abelnotes/features/pages_tray/presentation/pages_tray_overlay.dart'
    show showTrayMenu;
import 'package:abelnotes/features/pages_tray/presentation/tray_widgets.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/chapter_title.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/primitives/hw_glass.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Leaves the page manager and the notebook for another one (null = the
/// library); the editor implements it.
typedef PagesGoTo = Future<void> Function(String? notebookId);

/// Single-line popup-menu entry — keeps menus compact and visually
/// aligned with HwTheme (HwIcon + ink color instead of Material's
/// 56-px-tall ListTile). Shared by the chapter long-press menu.
Widget _hwMenuRow(HwPalette p, String icon, String label, {Color? color}) {
  final c = color ?? p.ink0;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      HwIcon(icon, size: 16, color: c),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 13, color: c)),
    ],
  );
}

/// Themed chapter picker bottom sheet (assign a page to a real chapter).
Future<String?> _pickChapter(
  BuildContext ctx,
  CanvasState s, {
  required String title,
  String? selectedChapterId,
}) {
  return showModalBottomSheet<String>(
    context: ctx,
    backgroundColor: Colors.transparent,
    builder: (shCtx) {
      final p = HwThemeScope.of(shCtx);
      Widget row({
        required String icon,
        required String label,
        required VoidCallback onTap,
        bool selected = false,
      }) {
        return InkWell(
          onTap: onTap,
          child: Container(
            color: selected ? p.accentSoft : null,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                HwIcon(icon, size: 18, color: p.ink0),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: p.ink0,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected) HwIcon('check', size: 16, color: p.accent),
              ],
            ),
          ),
        );
      }

      return SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: p.paper0,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(HwTheme.rLg)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: p.paper3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  title,
                  style: TextStyle(
                    color: p.ink1,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              ...s.metadata.chapters.map((chapter) => row(
                    icon: 'chapter',
                    label: chapterDisplayTitle(
                        AppLocalizations.of(shCtx), chapter.title),
                    selected: selectedChapterId == chapter.id,
                    onTap: () => Navigator.of(shCtx).pop(chapter.id),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────
//  PageManagerSheet
// ─────────────────────────────────────────────────────────────

/// How the destination slot was chosen (the card words it accordingly).
enum _SlotHow { after, start, chapterEnd, end }

class PageManagerSheet extends ConsumerStatefulWidget {
  final CanvasState initialState;

  /// Messenger captured from the canvas screen so SnackBars survive the
  /// bottom sheet route's lifecycle. On iPad, `ScaffoldMessenger.of(context)`
  /// resolved inside the sheet could resolve to a messenger that gets torn
  /// down with the sheet — leaving a "deleted" snackbar pinned to the
  /// bottom until the app is restarted.
  final ScaffoldMessengerState? parentMessenger;
  final PagesGoTo? onGoTo;
  const PageManagerSheet({
    super.key,
    required this.initialState,
    this.parentMessenger,
    this.onGoTo,
  });

  @override
  ConsumerState<PageManagerSheet> createState() => _PageManagerSheetState();
}

class _PageManagerSheetState extends ConsumerState<PageManagerSheet> {
  ScaffoldMessengerState get _messenger =>
      widget.parentMessenger ?? ScaffoldMessenger.of(context);

  final ScrollController _chapterStripCtrl = ScrollController();
  late final StateController<bool> _openFlag;

  /// Selected pages by id (survives reordering and filtering).
  final Set<String> _selected = {};
  bool _selectMode = false;
  String? _anchorId;
  bool _filterNone = false;

  late PasteSlot _slot;
  _SlotHow _how = _SlotHow.after;

  @override
  void initState() {
    super.initState();
    _openFlag = ref.read(pageManagerOpenProvider.notifier);
    Future.microtask(() {
      if (mounted) _openFlag.state = true;
    });
    final s = widget.initialState;
    _resetSlot(s);
  }

  @override
  void dispose() {
    widget.parentMessenger?.clearSnackBars();
    _chapterStripCtrl.dispose();
    Future.microtask(() => _openFlag.state = false);
    super.dispose();
  }

  // ── slot ──

  void _resetSlot(CanvasState s) {
    final cur = s.currentPageIndex < s.document.pages.length
        ? s.document.pages[s.currentPageIndex].pageId
        : null;
    _slot = defaultSlot(s.metadata.chapters, s.document, currentPageId: cur);
    if (s.document.pages.every((e) => e.pageId != cur)) {
      _how = s.document.pages.isEmpty
          ? _SlotHow.start
          : (s.metadata.chapters.isEmpty ? _SlotHow.end : _SlotHow.chapterEnd);
    } else {
      _how = _SlotHow.after;
    }
  }

  PasteSlot _validSlot(CanvasState s) {
    var slot = _slot;
    if (slot.afterPageId != null &&
        s.document.pages.every((e) => e.pageId != slot.afterPageId)) {
      _resetSlot(s);
      slot = _slot;
    }
    final chapters = s.metadata.chapters;
    if (chapters.isNotEmpty && !chapterExists(chapters, slot.chapterId)) {
      slot = PasteSlot(
          afterPageId: slot.afterPageId,
          chapterId: resolveChapter(chapters, s.document, slot));
    }
    if (chapters.isEmpty && slot.chapterId != null) {
      slot = PasteSlot(afterPageId: slot.afterPageId);
    }
    return slot;
  }

  // ── selection ──

  bool get _isSelecting => _selectMode;

  void _exitSelect() => setState(() {
        _selected.clear();
        _selectMode = false;
        _anchorId = null;
      });

  void _toggleSelect(CanvasState s, int docIdx) {
    final id = s.document.pages[docIdx].pageId;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      _anchorId = id;
    });
  }

  /// Shift-click: every page between the anchor and [docIdx] in visual
  /// order. Falls back to a toggle with no anchor or a hidden endpoint.
  void _selectRange(CanvasState s, int docIdx, List<int> visible) {
    final pages = s.document.pages;
    final anchor = _anchorId == null
        ? -1
        : pages.indexWhere((e) => e.pageId == _anchorId);
    final aPos = visible.indexOf(anchor);
    final bPos = visible.indexOf(docIdx);
    if (anchor < 0 || aPos < 0 || bPos < 0) {
      _toggleSelect(s, docIdx);
      return;
    }
    final lo = aPos < bPos ? aPos : bPos;
    final hi = aPos < bPos ? bPos : aPos;
    setState(() {
      for (final i in visible.sublist(lo, hi + 1)) {
        _selected.add(pages[i].pageId);
      }
      _selectMode = true;
    });
  }

  Set<int> _selectedIndices(CanvasState s) => {
        for (var i = 0; i < s.document.pages.length; i++)
          if (_selected.contains(s.document.pages[i].pageId)) i,
      };

  // ── actions on the selection ──

  Future<void> _capture(TrayMode mode, CanvasState s, Set<int> idx) async {
    await ref.read(pagesTrayProvider.notifier).capture(mode, s, idx);
    if (!mounted) return;
    final tray = ref.read(pagesTrayProvider).tray;
    setState(() {
      _selected.clear();
      _selectMode = false;
      _anchorId = null;
      if (tray != null) _resetSlot(ref.read(canvasProvider) ?? s);
    });
  }

  Future<void> _deleteSelected(CanvasState s) async {
    final idx = _selectedIndices(s);
    final ids = {for (final i in idx) s.document.pages[i].pageId};
    final l10n = AppLocalizations.of(context);
    final ok = await _confirmDelete(
      context,
      l10n.pmDeletePagesConfirm(idx.length),
      l10n.pmActionCannotBeUndone,
    );
    if (!ok || !mounted) return;
    ref.read(canvasProvider.notifier).deletePages(idx.toList());
    unawaited(ref
        .read(pagesTrayProvider.notifier)
        .pagesDeleted(s.metadata.id, ids));
    _exitSelect();
  }

  Future<bool> _confirmDelete(BuildContext ctx, String title, String body) async {
    final result = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(AppLocalizations.of(dCtx).pmCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: HwTheme.syncConflict),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(AppLocalizations.of(dCtx).pmDelete),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── destination ──

  void _pickSlot(CanvasState s, int docIdx, bool before) {
    final pages = s.document.pages;
    final tappedId = pages[docIdx].pageId;
    final afterId = before ? (docIdx > 0 ? pages[docIdx - 1].pageId : null) : tappedId;
    setState(() {
      _slot = slotAfter(s.metadata.chapters, s.document,
          afterPageId: afterId, tappedPageId: tappedId);
      _how = afterId == null ? _SlotHow.start : _SlotHow.after;
    });
  }

  Future<void> _confirm(CanvasState s) async {
    final ctl = ref.read(pagesTrayProvider.notifier);
    final out = await ctl.pasteIntoOpen(_validSlot(s));
    if (!mounted) return;
    if (out.done && out.newPageIds.isNotEmpty) {
      final now = ref.read(canvasProvider);
      // Pages that landed in a chapter the view hides: show everything.
      final landedIn = now?.document.pages
          .where((e) => out.newPageIds.contains(e.pageId))
          .map((e) => e.chapterId)
          .toSet();
      if (now != null &&
          landedIn != null &&
          now.activeChapterId != null &&
          !(landedIn.length == 1 && landedIn.first == now.activeChapterId)) {
        ref.read(canvasProvider.notifier).setActiveChapter(null);
      }
      setState(() {
        _filterNone = false;
        _selected.clear();
        _selectMode = false;
        if (now != null) {
          _slot = slotAfter(now.metadata.chapters, now.document,
              afterPageId: out.newPageIds.last, tappedPageId: out.newPageIds.last);
          _how = _SlotHow.after;
        }
      });
    }
  }

  Future<void> _pickChapterForSlot(BuildContext anchor, CanvasState s) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final p = HwThemeScope.of(anchor);
    final l = AppLocalizations.of(anchor);
    final rect = Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay));
    final cur = _validSlot(s).chapterId;
    final picked = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      color: p.paper0,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 34,
          child: Text(l.pgtChapterMenuHead,
              style: TextStyle(fontSize: 12, color: p.ink2)),
        ),
        for (final c in s.metadata.chapters)
          PopupMenuItem<String>(
            value: c.id,
            child: Row(children: [
              HwIcon('chapter', size: 16, color: p.ink0),
              const SizedBox(width: 10),
              Expanded(
                child: Text(chapterDisplayTitle(l, c.title),
                    style: TextStyle(fontSize: 14, color: p.ink0)),
              ),
              if (c.id == cur) HwIcon('check', size: 16, color: p.accent),
            ]),
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _slot = _slot.copyWith(chapterId: picked));
    }
  }

  Future<void> _anotherNotebook(CanvasState s, PagesTray tray) async {
    final picked = await showNotebookChooser(context,
        tray: tray, currentNotebookId: s.metadata.id);
    if (picked == null || !mounted) return;
    Navigator.pop(context);
    await widget.onGoTo?.call(picked == kChooserLibrary ? null : picked);
  }

  Future<void> _thisNotebook(PagesTray tray) async {
    Navigator.pop(context);
    await widget.onGoTo?.call(tray.sourceNotebookId);
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(canvasProvider) ?? widget.initialState;
    final tstate = ref.watch(pagesTrayProvider);
    final tray = tstate.tray;
    final pages = liveState.document.pages;
    final valid = {for (final e in pages) e.pageId};
    _selected.removeWhere((id) => !valid.contains(id));
    final selecting = _isSelecting;
    final place = tray != null && !selecting;
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);

    List<int> visible;
    if (_filterNone) {
      visible = [
        for (var i = 0; i < pages.length; i++)
          if (!chapterExists(liveState.metadata.chapters, pages[i].chapterId)) i,
      ];
    } else {
      visible = liveState.filteredPageIndices;
    }
    final chapters = liveState.metadata.chapters;
    final unfiled = chapters.isNotEmpty &&
        pages.any((e) => !chapterExists(chapters, e.chapterId));
    final hasChips = chapters.isNotEmpty;
    final moving = tray != null &&
            tray.isMove &&
            tray.sourceNotebookId == liveState.metadata.id
        ? tray.pageIds
        : const <String>{};
    final landing = tstate.landing;

    final headerH = 8.0 + 62 + (hasChips ? 50 : 4);
    final panelH = place ? (tray.isMove ? 190.0 : 150.0) : (selecting ? (tray != null ? 150.0 : 88.0) : 0.0);
    final toastH = tstate.toast != null ? 64.0 : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollController) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              child: ColoredBox(
                color: p.paper0,
                child: Stack(children: [
                  Positioned.fill(
                    child: PageGrid(
                      scrollController: scrollController,
                      liveState: liveState,
                      visibleIndices: visible,
                      mode: selecting
                          ? PageGridMode.select
                          : (place ? PageGridMode.place : PageGridMode.browse),
                      selectedIds: _selected,
                      movingIds: moving,
                      landingIds: landing?.pageIds ?? const {},
                      landingStamp: landing?.stamp ?? 0,
                      tray: tray,
                      slot: place ? _validSlot(liveState) : null,
                      ghostLabel: tray == null
                          ? ''
                          : (tray.isMove ? l10n.pgtMoveHere : l10n.pgtPasteHere),
                      topPadding: headerH + 6,
                      bottomPadding: panelH + toastH + 28,
                      hint: place
                          ? _hint(ctx, tray.isMove)
                          : null,
                      onTapPage: (index) {
                        ref.read(canvasProvider.notifier).goToPage(index);
                        Navigator.pop(ctx);
                      },
                      onPageAction: (docIndex, action) =>
                          _pageAction(ctx, liveState, docIndex, action),
                      onToggleSelect: (i) => _toggleSelect(liveState, i),
                      onRangeSelect: (i, vis) {
                        _selectRange(liveState, i, vis);
                      },
                      onLongPressToSelect: (i) => setState(() {
                        _selectMode = true;
                        _selected.add(liveState.document.pages[i].pageId);
                      }),
                      onPickSlot: (i, before) => _pickSlot(liveState, i, before),
                      onConfirmGhost: () => _confirm(liveState),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _header(ctx, liveState, visible, unfiled, hasChips),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12 + MediaQuery.paddingOf(ctx).bottom,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tstate.toast != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TrayToastView(
                              key: ValueKey('t${tstate.toast!.id}'),
                              toast: tstate.toast!,
                              onUndo: () => ref
                                  .read(pagesTrayProvider.notifier)
                                  .undoLast(),
                              onShow: () {},
                              onClose: () => ref
                                  .read(pagesTrayProvider.notifier)
                                  .dismissToast(),
                              onHover: (h) => ref
                                  .read(pagesTrayProvider.notifier)
                                  .holdToast(h),
                            ),
                          ),
                        if (selecting && tray != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MiniTray(
                                tray: tray,
                                inNotebookId: liveState.metadata.id),
                          ),
                        if (selecting)
                          _ActionBar(
                            enabled: _selected.isNotEmpty && !tstate.busy,
                            onCopy: () => _capture(TrayMode.copy, liveState,
                                _selectedIndices(liveState)),
                            onMove: () => _capture(TrayMode.move, liveState,
                                _selectedIndices(liveState)),
                            onDuplicate: () {
                              final ids = _selected.toSet();
                              ref
                                  .read(pagesTrayProvider.notifier)
                                  .duplicatePages(ids);
                              _exitSelect();
                            },
                            onDelete: () => _deleteSelected(liveState),
                          ),
                        if (place)
                          _DestCard(
                            tray: tray,
                            state: liveState,
                            slot: _validSlot(liveState),
                            how: _how,
                            busy: tstate.busy,
                            onConfirm: () => _confirm(liveState),
                            onThisNotebook: () => _thisNotebook(tray),
                            onAnother: () => _anotherNotebook(liveState, tray),
                            onChapter: (c) => _pickChapterForSlot(c, liveState),
                          ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hint(BuildContext ctx, bool moving) {
    final p = HwThemeScope.of(ctx);
    final l = AppLocalizations.of(ctx);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: HwIcon('pin', size: 16, color: p.accent),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(moving ? l.pgtHintPlaceMove : l.pgtHintPlaceCopy,
            style: TextStyle(fontSize: 13, color: p.ink2, height: 1.3)),
      ),
    ]);
  }

  // ── header ──

  Widget _header(BuildContext ctx, CanvasState s, List<int> visible,
      bool unfiled, bool hasChips) {
    final p = HwThemeScope.of(ctx);
    final l10n = AppLocalizations.of(ctx);
    final selecting = _isSelecting;
    final tray = ref.watch(pagesTrayProvider).tray;
    final place = tray != null && !selecting;
    final chapters = s.metadata.chapters;
    final slotChapter = place ? _validSlot(s).chapterId : null;
    final allVisible = visible.isNotEmpty &&
        visible.every((i) => _selected.contains(s.document.pages[i].pageId));

    Widget textBtn(String label, VoidCallback onTap, {bool solid = false}) =>
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: solid ? p.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: solid ? p.onAccent : p.accentDeep)),
          ),
        );

    final title = selecting
        ? (_selected.isEmpty ? l10n.pgtSelectPages : l10n.pmSelectedCount(_selected.length))
        : l10n.pgtTitlePages;
    final eyebrow = selecting
        ? s.metadata.title
        : l10n.pgtEyebrow(s.metadata.title, s.pageCount);

    return HwGlass(
      strong: true,
      shadow: false,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 5,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: p.glassLine,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: p.ink2)),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HwType.largeTitle
                            .copyWith(color: p.ink0, fontSize: 28)),
                  ],
                ),
              ),
              if (selecting) ...[
                textBtn(allVisible ? l10n.pgtNone : l10n.pgtAll, () {
                  setState(() {
                    if (allVisible) {
                      _selected.clear();
                    } else {
                      for (final i in visible) {
                        _selected.add(s.document.pages[i].pageId);
                      }
                    }
                  });
                }),
                const SizedBox(width: 4),
                textBtn(l10n.pgtDone, _exitSelect, solid: true),
              ] else ...[
                if (s.pageCount > 1)
                  HwButton.icon(
                    icon: const HwIcon('search', size: 18),
                    tooltip: l10n.pmGoToPageTooltip,
                    onPressed: () => _promptJumpToPage(ctx, s),
                  ),
                textBtn(l10n.pgtSelect, () => setState(() {
                      _selectMode = true;
                    })),
                HwButton.icon(
                  icon: HwIcon('plus', size: 18, color: p.accent),
                  onPressed: () => ref.read(canvasProvider.notifier).addPage(),
                  tooltip: l10n.pmAddPage,
                ),
                HwButton.icon(
                  icon: const HwIcon('x', size: 18),
                  tooltip: l10n.pmClose,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ],
          ),
          if (hasChips)
            SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Listener(
                  onPointerSignal: (signal) {
                    if (signal is PointerScrollEvent &&
                        _chapterStripCtrl.hasClients) {
                      final dy = signal.scrollDelta.dy;
                      final dx = signal.scrollDelta.dx;
                      final delta = dy.abs() > dx.abs() ? dy : dx;
                      final next = (_chapterStripCtrl.offset + delta).clamp(
                        0.0,
                        _chapterStripCtrl.position.maxScrollExtent,
                      );
                      _chapterStripCtrl.jumpTo(next);
                    }
                  },
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(ctx).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: ListView(
                      controller: _chapterStripCtrl,
                      scrollDirection: Axis.horizontal,
                      children: [
                        _chip(
                          label: l10n.pgtAll,
                          count: s.pageCount,
                          selected: s.activeChapterId == null && !_filterNone,
                          onTap: () {
                            setState(() => _filterNone = false);
                            ref
                                .read(canvasProvider.notifier)
                                .setActiveChapter(null);
                          },
                        ),
                        for (final entry in chapters.asMap().entries)
                          _chapterChip(ctx, s, entry.key, entry.value, place,
                              slotChapter),
                        if (unfiled)
                          _chip(
                            label: l10n.pgtNoChapter,
                            count: s.document.pages
                                .where((e) => !chapterExists(chapters, e.chapterId))
                                .length,
                            selected: _filterNone,
                            onTap: () {
                              setState(() => _filterNone = true);
                              ref
                                  .read(canvasProvider.notifier)
                                  .setActiveChapter(null);
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _AddChip(
                            tooltip: l10n.pmNewChapter,
                            onTap: () async {
                              final title = await _promptForTextLocal(
                                  ctx, l10n.pmNewChapter, l10n.pmChapterNameHint);
                              if (title != null && title.trim().isNotEmpty) {
                                ref
                                    .read(canvasProvider.notifier)
                                    .addChapter(title.trim());
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    Color? dot,
    bool highlighted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _ChapterChip(
        label: label,
        count: count,
        selected: selected,
        dot: dot,
        highlighted: highlighted,
        onTap: onTap,
      ),
    );
  }

  Widget _chapterChip(BuildContext ctx, CanvasState s, int chapIdx,
      Chapter chapter, bool place, String? slotChapter) {
    final p = HwThemeScope.of(ctx);
    final l10n = AppLocalizations.of(ctx);
    final isActive = s.activeChapterId == chapter.id && !_filterNone;
    final count = s.document.pages.where((e) => e.chapterId == chapter.id).length;
    final chip = _ChapterChip(
      label: chapterDisplayTitle(l10n, chapter.title),
      count: count,
      selected: isActive,
      dot: kChapterDots[chapIdx % kChapterDots.length],
      highlighted: place && slotChapter == chapter.id && !isActive,
      onTap: () {
        setState(() => _filterNone = false);
        ref.read(canvasProvider.notifier).setActiveChapter(chapter.id);
        if (place) {
          final now = ref.read(canvasProvider) ?? s;
          setState(() {
            _slot = endOfChapterSlot(
                now.metadata.chapters, now.document, chapter.id);
            _how = _SlotHow.chapterEnd;
          });
        }
      },
    );
    return DragTarget<int>(
      key: ValueKey(chapter.id),
      onWillAcceptWithDetails: (details) => details.data != chapIdx,
      onAcceptWithDetails: (details) {
        ref.read(canvasProvider.notifier).reorderChapters(details.data, chapIdx);
      },
      builder: (ctx2, accepted, rejected) {
        return LongPressDraggable<int>(
          data: chapIdx,
          axis: Axis.horizontal,
          delay: const Duration(milliseconds: 200),
          feedback: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                chapterDisplayTitle(l10n, chapter.title),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                  color: p.accent,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: Padding(padding: const EdgeInsets.only(right: 8), child: chip),
          ),
          onDragCompleted: () {},
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onSecondaryTap: () => _showChapterEditMenuLocal(ctx2, chapter),
              onLongPress: () => _showChapterEditMenuLocal(ctx2, chapter),
              child: accepted.isNotEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: p.accent, width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: chip,
                    )
                  : chip,
            ),
          ),
        );
      },
    );
  }

  // ── per-page menu ──

  Future<void> _pageAction(
      BuildContext ctx, CanvasState s, int docIndex, String action) async {
    final l10n = AppLocalizations.of(ctx);
    final notifier = ref.read(canvasProvider.notifier);
    switch (action) {
      case 'copy':
        await _capture(TrayMode.copy, s, {docIndex});
      case 'move':
        await _capture(TrayMode.move, s, {docIndex});
      case 'insert_before':
        notifier.insertPageAt(docIndex);
      case 'insert_after':
        notifier.insertPageAt(docIndex + 1);
      case 'duplicate':
        notifier.duplicatePage(docIndex);
      case 'moveto':
        await _movePageToNumber(ctx, s, docIndex);
      case 'chapter':
        await _showChapterPickerForPage(ctx, s, docIndex);
      case 'delete':
        // One-click delete with SnackBar undo: deletePage pushes an undo
        // entry, so the Undo button can roll it back.
        final id = s.document.pages[docIndex].pageId;
        notifier.deletePage(docIndex);
        unawaited(ref
            .read(pagesTrayProvider.notifier)
            .pagesDeleted(s.metadata.id, {id}));
        HapticFeedback.mediumImpact();
        _messenger.hideCurrentSnackBar();
        _messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.pmPageDeleted(docIndex + 1)),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.pmUndo,
              onPressed: () => ref.read(canvasProvider.notifier).undo(),
            ),
          ),
        );
    }
  }

  Future<void> _showChapterPickerForPage(
      BuildContext ctx, CanvasState s, int pageIndex) async {
    final l10n = AppLocalizations.of(ctx);
    if (s.metadata.chapters.isEmpty) {
      _messenger.showSnackBar(
        SnackBar(content: Text(l10n.pmCreateChapterFirst)),
      );
      return;
    }
    final currentId = s.document.pages[pageIndex].chapterId;
    final selectedId = await _pickChapter(
      ctx,
      s,
      title: l10n.pmAssignChapter,
      selectedChapterId: currentId,
    );
    if (!mounted || selectedId == null) return;
    ref.read(canvasProvider.notifier).assignPageToChapter(pageIndex, selectedId);
  }

  Future<void> _showChapterEditMenuLocal(BuildContext ctx, Chapter chapter) async {
    final box = ctx.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final p = HwThemeScope.of(ctx);
    final l10n = AppLocalizations.of(ctx);
    final action = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'rename', child: _hwMenuRow(p, 'pen', l10n.pmRename)),
        PopupMenuItem(
          value: 'delete',
          child: _hwMenuRow(p, 'trash', l10n.pmDelete,
              color: HwTheme.syncConflict),
        ),
      ],
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      final newTitle = await _promptForTextLocal(
          ctx, l10n.pmRenameChapter, l10n.pmChapterNameHint,
          initial: chapterDisplayTitle(l10n, chapter.title));
      if (newTitle != null && newTitle.trim().isNotEmpty && mounted) {
        ref.read(canvasProvider.notifier).renameChapter(chapter.id, newTitle.trim());
      }
    } else if (action == 'delete') {
      if (!ctx.mounted) return;
      final confirm = await showDialog<bool>(
        context: ctx,
        builder: (dCtx) => AlertDialog(
          title: Text(l10n.pmDeleteChapter),
          content: Text(l10n.pmDeleteChapterConfirm(
              chapterDisplayTitle(l10n, chapter.title))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(l10n.pmCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(l10n.pmDelete),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        ref.read(canvasProvider.notifier).deleteChapter(chapter.id);
      }
    }
  }

  /// Ask for a destination page number and move the page there. With a
  /// chapter filter active, the typed number counts within the filtered view
  /// (same convention as jump-to-page).
  Future<void> _movePageToNumber(
      BuildContext ctx, CanvasState s, int docIndex) async {
    final filtered = s.filteredPageIndices;
    final maxN = filtered.isEmpty ? s.pageCount : filtered.length;
    if (maxN <= 1) return;
    final l10n = AppLocalizations.of(ctx);
    final result = await promptPageNumber(ctx,
        title: l10n.pmMoveToPage,
        hint: l10n.pmPageRangeHint(maxN),
        cancel: l10n.pmCancel,
        ok: l10n.pmMove);
    if (result == null || !mounted) return;
    final clamped = (result - 1).clamp(0, maxN - 1);
    final targetPosition =
        filtered.isEmpty ? clamped + 1 : filtered[clamped] + 1;
    ref
        .read(canvasProvider.notifier)
        .movePagesToPosition([docIndex], targetPosition);
  }

  Future<void> _promptJumpToPage(BuildContext ctx, CanvasState s) async {
    final filtered = s.filteredPageIndices;
    final maxN = filtered.isEmpty ? s.pageCount : filtered.length;
    if (maxN <= 0) return;
    final l10n = AppLocalizations.of(ctx);
    final result = await promptPageNumber(ctx,
        title: l10n.pmGoToPage,
        hint: l10n.pmPageRangeHint(maxN),
        cancel: l10n.pmCancel,
        ok: l10n.pmGo);
    if (result == null || !mounted) return;
    final clamped = (result - 1).clamp(0, maxN - 1);
    final target = filtered.isEmpty ? clamped : filtered[clamped];
    ref.read(canvasProvider.notifier).goToPage(target);
    if (ctx.mounted) Navigator.pop(ctx);
  }

  Future<String?> _promptForTextLocal(
    BuildContext ctx, String title, String hint, {String? initial}) async {
    String value = initial ?? '';
    return showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          autofocus: true,
          initialValue: value,
          decoration: InputDecoration(hintText: hint),
          onChanged: (v) => value = v,
          onFieldSubmitted: (v) => Navigator.pop(dCtx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(AppLocalizations.of(dCtx).pmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, value),
            child: Text(AppLocalizations.of(dCtx).pmOk),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Chips
// ─────────────────────────────────────────────────────────────

class _ChapterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final bool highlighted;
  final Color? dot;
  final VoidCallback onTap;
  const _ChapterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.highlighted,
    required this.dot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final fg = selected ? p.onAccent : (highlighted ? p.accentDeep : p.ink0);
    return HwPressable(
      pressedScale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected
                ? p.accent
                : (highlighted ? p.accentSoft : p.paper2),
            borderRadius: BorderRadius.circular(16),
            border: highlighted && !selected
                ? Border.all(color: p.accent, width: 1.5)
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: p.onAccent, width: 1.5)
                      : null,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
            const SizedBox(width: 7),
            Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    color: fg.withValues(alpha: 0.65),
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  const _AddChip({required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: p.paper2, shape: BoxShape.circle),
          child: Center(child: HwIcon('plus', size: 16, color: p.ink2)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Bottom panel pieces
// ─────────────────────────────────────────────────────────────

/// Copy · Move · Duplicate · Delete (fits a phone: four equal slots).
class _ActionBar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  const _ActionBar({
    required this.enabled,
    required this.onCopy,
    required this.onMove,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l = AppLocalizations.of(context);
    Widget btn(String icon, String label, Color color, VoidCallback onTap) {
      return Expanded(
        child: Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: HwPressable(
            enabled: enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? onTap : null,
              child: Opacity(
                opacity: enabled ? 1 : 0.35,
                child: SizedBox(
                  height: 56,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HwIcon(icon, size: 20, color: color),
                      const SizedBox(height: 3),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: color)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget sep() => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        color: p.glassLine);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: HwGlass(
        borderRadius: BorderRadius.circular(26),
        padding: const EdgeInsets.all(6),
        child: Row(children: [
          btn('copy', l.pgtCopy, p.accentDeep, onCopy),
          btn('move', l.pgtMove, p.accentDeep, onMove),
          sep(),
          btn('duplicate', l.pmDuplicate, p.ink0, onDuplicate),
          sep(),
          btn('trash', l.pmDelete, HwTheme.syncConflict, onDelete),
        ]),
      ),
    );
  }
}

/// The tray, small, above the action bar while selecting.
class _MiniTray extends ConsumerStatefulWidget {
  final PagesTray tray;
  final String inNotebookId;
  const _MiniTray({required this.tray, required this.inNotebookId});

  @override
  ConsumerState<_MiniTray> createState() => _MiniTrayState();
}

class _MiniTrayState extends ConsumerState<_MiniTray> {
  final _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tray = widget.tray;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: HwGlass(
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              key: _anchor,
              behavior: HitTestBehavior.opaque,
              onTap: () => showTrayMenu(ref, _anchor.currentContext!, tray,
                  inEditor: true,
                  inPages: true,
                  currentNotebookId: widget.inNotebookId),
              child: TrayInfo(tray: tray, fanScale: 0.82),
            ),
          ),
          const SizedBox(width: 8),
          TrayRoundButton(
            icon: 'x',
            tooltip: tray.isMove ? l.pgtCancelMove : l.pgtClearTray,
            onTap: ref.read(pagesTrayProvider.notifier).cancel,
          ),
        ]),
      ),
    );
  }
}

/// Where the tray lands, and the button that does it.
class _DestCard extends ConsumerStatefulWidget {
  final PagesTray tray;
  final CanvasState state;
  final PasteSlot slot;
  final _SlotHow how;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onThisNotebook;
  final VoidCallback onAnother;
  final void Function(BuildContext anchor) onChapter;
  const _DestCard({
    required this.tray,
    required this.state,
    required this.slot,
    required this.how,
    required this.busy,
    required this.onConfirm,
    required this.onThisNotebook,
    required this.onAnother,
    required this.onChapter,
  });

  @override
  ConsumerState<_DestCard> createState() => _DestCardState();
}

class _DestCardState extends ConsumerState<_DestCard> {
  final _trayAnchor = GlobalKey();
  final _chapterAnchor = GlobalKey();

  String _position(AppLocalizations l) {
    final s = widget.state;
    final slot = widget.slot;
    switch (widget.how) {
      case _SlotHow.chapterEnd:
        final c = s.metadata.chapters.where((c) => c.id == slot.chapterId);
        return l.pgtPosChapterEnd(
            c.isEmpty ? '' : chapterDisplayTitle(l, c.first.title));
      case _SlotHow.end:
        return l.pgtPosEnd;
      default:
        final after = widget.tray.isMove
            ? skipMoving(s.document, slot.afterPageId,
                widget.tray.sourceNotebookId == s.metadata.id
                    ? widget.tray.pageIds
                    : const {})
            : slot.afterPageId;
        if (after == null) return l.pgtPosStart;
        final i = s.document.pages.indexWhere((e) => e.pageId == after);
        return i < 0 ? l.pgtPosEnd : l.pgtPosAfter(i + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l = AppLocalizations.of(context);
    final tray = widget.tray;
    final s = widget.state;
    final move = tray.isMove;
    final here = tray.sourceNotebookId == s.metadata.id;
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final chapters = s.metadata.chapters;
    final chapter = chapters.where((c) => c.id == widget.slot.chapterId);
    final nb = s.metadata.title;

    Widget seg(String label, bool on, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? p.paper0 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: on
                    ? [
                        BoxShadow(
                            color: p.ink0.withValues(alpha: 0.18),
                            blurRadius: 4,
                            offset: const Offset(0, 1)),
                      ]
                    : null,
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: on ? p.ink0 : p.ink2)),
            ),
          ),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: HwGlass(
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (move) ...[
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    color: p.glassLine,
                    borderRadius: BorderRadius.circular(15)),
                child: Row(children: [
                  seg(l.pgtThisNotebook, here, widget.onThisNotebook),
                  const SizedBox(width: 2),
                  seg(l.pgtAnotherNotebook, !here, widget.onAnother),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Expanded(
                child: GestureDetector(
                  key: _trayAnchor,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showTrayMenu(ref, _trayAnchor.currentContext!, tray,
                      inEditor: true,
                      inPages: true,
                      currentNotebookId: s.metadata.id),
                  child: Row(children: [
                    Expanded(child: TrayInfo(tray: tray)),
                    HwIcon('chevron-up', size: 16, color: p.ink3),
                    const SizedBox(width: 6),
                  ]),
                ),
              ),
              TrayRoundButton(
                icon: 'x',
                tooltip: move ? l.pgtCancelMove : l.pgtClearTray,
                onTap: ref.read(pagesTrayProvider.notifier).cancel,
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        (move ? l.pgtMoveToNb(nb) : l.pgtPasteIntoNb(nb))
                            .toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                            color: p.ink2)),
                    const SizedBox(height: 3),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        HwIcon('pin', size: 16, color: p.accent),
                        Text(_position(l),
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: p.ink0)),
                        if (chapters.isNotEmpty && chapter.isNotEmpty)
                          GestureDetector(
                            key: _chapterAnchor,
                            onTap: () => widget.onChapter(_chapterAnchor.currentContext!),
                            child: Container(
                              height: 26,
                              padding: const EdgeInsets.fromLTRB(9, 0, 6, 0),
                              decoration: BoxDecoration(
                                  color: p.accentSoft,
                                  borderRadius: BorderRadius.circular(13)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(chapterDisplayTitle(l, chapter.first.title),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: p.accentDeep)),
                                const SizedBox(width: 4),
                                HwIcon('chevron-down',
                                    size: 13, color: p.accentDeep),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              TrayPrimaryButton(
                icon: move ? 'move' : 'paste',
                label: move
                    ? l.pgtMoveHere
                    : (narrow ? l.pgtPasteCountShort(tray.count) : l.pgtPasteCount(tray.count)),
                onTap: widget.busy ? null : widget.onConfirm,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Asks for a page number (move to / go to page). Null when cancelled.
Future<int?> promptPageNumber(BuildContext ctx,
    {required String title,
    required String hint,
    required String cancel,
    required String ok}) async {
  final result = await showDialog<int>(
    context: ctx,
    builder: (dCtx) => TextControllerScope(builder: (_, controller) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(dCtx, int.tryParse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(cancel)),
        TextButton(
          onPressed: () => Navigator.pop(dCtx, int.tryParse(controller.text)),
          child: Text(ok),
        ),
      ],
    )),
  );
  return result;
}
