import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/pages_tray/application/pages_tray_provider.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/features/pages_tray/presentation/tray_widgets.dart';
import 'package:abelnotes/features/sync/sync_notices.dart' show syncNavigatorKey;
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/hw_glass.dart';
import 'package:abelnotes/ui/primitives/hw_motion_widgets.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

final _coverProvider = Provider<bool>((ref) {
  void listener() => ref.invalidateSelf();
  TrayRouteObserver.coverOnTop.addListener(listener);
  ref.onDispose(() => TrayRouteObserver.coverOnTop.removeListener(listener));
  return TrayRouteObserver.coverOnTop.value;
});

/// Opens the tray's menu (the pill and the page manager share it). [anchor]
/// is the widget the menu hangs from; [inPages] hides "Choose where".
Future<void> showTrayMenu(
  WidgetRef ref,
  BuildContext anchor,
  PagesTray tray, {
  required bool inEditor,
  required bool inPages,
  String? currentNotebookId,
}) async {
  final nav = syncNavigatorKey.currentState?.overlay?.context;
  final box = anchor.findRenderObject() as RenderBox?;
  if (nav == null || box == null) return;
  final l = AppLocalizations.of(nav);
  final p = HwThemeScope.of(nav);
  final overlay = nav.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final rect = Rect.fromPoints(
      topLeft, box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay));
  final canOpenSource =
      !tray.sourceDeleted && tray.sourceNotebookId != currentNotebookId;

  PopupMenuItem<String> row(String v, String icon, String label,
      {String? hint, bool enabled = true}) {
    return PopupMenuItem<String>(
      value: v,
      enabled: enabled,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        HwIcon(icon, size: 16, color: p.ink0),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: p.ink0)),
              if (hint != null)
                Text(hint, style: TextStyle(fontSize: 12, color: p.ink2)),
            ],
          ),
        ),
      ]),
    );
  }

  // The pill hides while the menu is up, so its ref is gone once this returns.
  final trayCtl = ref.read(pagesTrayProvider.notifier);
  final navCtl = ref.read(pagesTrayNavProvider.notifier);
  final picked = await showMenu<String>(
    context: nav,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    color: p.paper0,
    items: [
      if (inEditor && !inPages)
        row('where', 'pages', l.pgtChooseWhere,
            hint: l.pgtChooseWhereHint),
      if (canOpenSource)
        row('source', 'book', l.pgtOpenSource(tray.sourceTitle),
            hint: l.pgtOpenSourceHint),
      if (tray.isMove)
        row('cancel', 'undo', l.pgtCancelMove, hint: l.pgtCancelMoveHint)
      else
        row('clear', 'x', l.pgtClearTray),
      // Last: the menu opens over the tray, and a second tap on the
      // same spot lands here instead of on "Cancel move".
      if (tray.saved)
        PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const HwIcon('saved', size: 15, color: HwTheme.syncOk),
            const SizedBox(width: 8),
            Flexible(
              child: Text(l.pgtSavedLong,
                  style: TextStyle(fontSize: 12, color: p.ink2)),
            ),
          ]),
        ),
    ],
  );
  switch (picked) {
    case 'where':
      if (currentNotebookId != null) {
        navCtl.state = TrayNavRequest(currentNotebookId);
      }
    case 'source':
      navCtl.state = TrayNavRequest(tray.sourceNotebookId);
    case 'cancel' || 'clear':
      trayCtl.cancel();
  }
}

/// Tells the overlay when a sheet, dialog or menu covers the screen, so the
/// tray (painted above the navigator) does not sit on top of its content.
class TrayRouteObserver extends NavigatorObserver {
  static final ValueNotifier<bool> coverOnTop = ValueNotifier<bool>(false);

  /// Ticks when a full screen comes or goes (not sheets, dialogs or menus).
  static final ValueNotifier<int> screenChanges = ValueNotifier<int>(0);

  static void _screen(Route<dynamic>? r) {
    if (r is PageRoute) screenChanges.value++;
  }

  static bool _covers(Route<dynamic>? r) => r is PopupRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    coverOnTop.value = _covers(route);
    _screen(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    coverOnTop.value = _covers(previousRoute);
    _screen(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      coverOnTop.value = _covers(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    coverOnTop.value = _covers(newRoute);
    _screen(newRoute);
  }
}

/// The tray and toasts that follow the user across library and editor. The
/// page manager draws its own, so everything here hides while it is open.
class PagesTrayOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const PagesTrayOverlay({super.key, required this.child});

  @override
  ConsumerState<PagesTrayOverlay> createState() => _PagesTrayOverlayState();
}

class _PagesTrayOverlayState extends ConsumerState<PagesTrayOverlay> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pagesTrayProvider.notifier).start());
    TrayRouteObserver.screenChanges.addListener(_movedOn);
  }

  @override
  void dispose() {
    TrayRouteObserver.screenChanges.removeListener(_movedOn);
    super.dispose();
  }

  void _movedOn() => ref.read(pagesTrayProvider.notifier).dismissUndoToast();

  @override
  Widget build(BuildContext context) {
    // A new edit on the canvas means the user moved on from the Undo offer.
    ref.listen<int?>(canvasProvider.select((s) => s?.undoStack.length),
        (prev, next) {
      if (prev != null && next != null && next > prev) _movedOn();
    });
    final child = widget.child;
    final st = ref.watch(pagesTrayProvider);
    final pmOpen = ref.watch(pageManagerOpenProvider);
    final inEditor = ref.watch(canvasProvider.select((s) => s != null));
    final covered = ref.watch(_coverProvider);
    final tray = pmOpen || covered ? null : st.tray;
    final toast = pmOpen ? null : st.toast;
    return Stack(children: [
      child,
      if (tray != null && inEditor)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 52 + 8,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.topCenter,
            child: _Materialized(
                key: const ValueKey('tray-editor'),
                child: _TrayPill(tray: tray, inEditor: true, busy: st.busy)),
          ),
        ),
      if ((tray != null && !inEditor) || toast != null)
        Positioned(
          left: 16,
          right: 16,
          // The phone library has a footer bar of its own to clear.
          bottom: 18 +
              MediaQuery.paddingOf(context).bottom +
              (!inEditor && MediaQuery.sizeOf(context).width < 900 ? 44 : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (toast != null)
                Padding(
                  padding: EdgeInsets.only(bottom: tray != null && !inEditor ? 10 : 0),
                  child: _Materialized(
                    key: ValueKey('toast-${toast.id}'),
                    child: TrayToastView(
                      toast: toast,
                      onUndo: () =>
                          ref.read(pagesTrayProvider.notifier).undoLast(),
                      onShow: () {
                        final id = toast.showNotebookId;
                        if (id == null) return;
                        ref.read(pagesTrayProvider.notifier).dismissToast();
                        ref.read(pagesTrayNavProvider.notifier).state =
                            TrayNavRequest(id, toast.landingIds);
                      },
                      onClose: () =>
                          ref.read(pagesTrayProvider.notifier).dismissToast(),
                      onHover: (h) =>
                          ref.read(pagesTrayProvider.notifier).holdToast(h),
                    ),
                  ),
                ),
              if (tray != null && !inEditor)
                _Materialized(
                    key: const ValueKey('tray-lib'),
                    child:
                        _TrayPill(tray: tray, inEditor: false, busy: st.busy)),
            ],
          ),
        ),
    ]);
  }
}

/// Fades and scales its child in once, from the bottom.
class _Materialized extends StatelessWidget {
  final Widget child;
  const _Materialized({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return HwMaterialize(
      visible: true,
      alignment: Alignment.bottomCenter,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _TrayPill extends ConsumerStatefulWidget {
  final PagesTray tray;
  final bool inEditor;
  final bool busy;
  const _TrayPill(
      {required this.tray, required this.inEditor, required this.busy});

  @override
  ConsumerState<_TrayPill> createState() => _TrayPillState();
}

class _TrayPillState extends ConsumerState<_TrayPill> {
  final _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final tray = widget.tray;
    final inEditor = widget.inEditor;
    final busy = widget.busy;
    final anchor = _anchor;
    final l = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final ctl = ref.read(pagesTrayProvider.notifier);
    final cs = inEditor ? ref.watch(canvasProvider) : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: HwGlass(
        strong: true,
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: l.pgtTrayOptions,
              child: GestureDetector(
                key: anchor,
                behavior: HitTestBehavior.opaque,
                onTap: () => showTrayMenu(ref, anchor.currentContext!, tray,
                    inEditor: inEditor,
                    inPages: false,
                    currentNotebookId: cs?.metadata.id),
                child: Row(children: [
                  Expanded(child: TrayInfo(tray: tray)),
                  HwIcon('chevron-up', size: 16, color: p.ink3),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
          if (inEditor && cs != null) ...[
            TrayPrimaryButton(
              icon: tray.isMove ? 'move' : 'paste',
              label: narrow
                  ? (tray.isMove ? l.pgtMoveShort : l.pgtPasteShort)
                  : (tray.isMove ? l.pgtMoveHere : l.pgtPasteHere),
              onTap: busy
                  ? null
                  : () {
                      final slot = defaultSlot(
                          cs.metadata.chapters, cs.document,
                          currentPageId: cs.currentPageIndex <
                                  cs.document.pages.length
                              ? cs.document.pages[cs.currentPageIndex].pageId
                              : null);
                      ctl.pasteIntoOpen(slot);
                    },
            ),
            const SizedBox(width: 8),
          ],
          TrayRoundButton(
            icon: 'x',
            tooltip: tray.isMove ? l.pgtCancelMove : l.pgtClearTray,
            onTap: ctl.cancel,
          ),
        ]),
      ),
    );
  }
}
