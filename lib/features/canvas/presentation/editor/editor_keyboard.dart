// Keyboard shortcuts of the editor as tables of actions, taking the ref and
// the screen callbacks explicitly. Same keys and focus rules as before.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/clipboard_flow.dart';

typedef _KeyAction = KeyEventResult Function(KeyEvent event);

class EditorKeyboard {
  EditorKeyboard({
    required this.context,
    required this.ref,
    required this.clipboard,
    required this.findHasFocus,
    required this.isFindOpen,
    required this.openFind,
    required this.closeFind,
    required this.save,
    required this.pickTool,
    required this.showShortcutHelp,
    required this.toast,
    required this.isPresentationMode,
    required this.exitPresentationMode,
    required this.isPopupOpen,
    required this.closePopup,
  });

  final BuildContext context;
  final WidgetRef ref;
  final ClipboardFlow clipboard;
  final bool Function() findHasFocus;
  final bool Function() isFindOpen;
  final void Function() openFind;
  final void Function() closeFind;
  final void Function() save;
  final void Function(CanvasTool tool) pickTool;
  final void Function() showShortcutHelp;
  final void Function(String message) toast;
  final bool Function() isPresentationMode;
  final void Function() exitPresentationMode;
  final bool Function() isPopupOpen;
  final void Function() closePopup;

  // Tracks same-direction arrow presses: a gap over ~220 ms (OS key-repeat
  // is ~30 Hz) resets the count, a long hold jumps several pages per tick.
  DateTime? _lastArrowAt;
  int _lastArrowDir = 0; // -1 = left, 1 = right
  int _arrowHoldCount = 0;

  /// Keys a preview (read-only notebook) still answers: zoom and paging.
  static final Set<LogicalKeyboardKey> previewKeys = {
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.equal,
    LogicalKeyboardKey.add,
    LogicalKeyboardKey.numpadAdd,
    LogicalKeyboardKey.minus,
    LogicalKeyboardKey.numpadSubtract,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.escape,
  };

  CanvasNotifier get _notifier => ref.read(canvasProvider.notifier);

  KeyEventResult handle(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Typing in the find field: letters are text, not tool shortcuts.
    if (findHasFocus()) return KeyEventResult.ignored;
    // The rest of the notebook is still loading: no shortcut acts yet.
    if (_notifier.pagesLoading.value) return KeyEventResult.handled;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    // A preview only reads: zoom and paging, no shortcut that edits.
    if (_notifier.isPreview && !previewKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final action = (ctrl ? _ctrl : _plain)[key] ?? _always[key];
    return action == null ? KeyEventResult.ignored : action(event);
  }

  KeyEventResult _handled(void Function() run) {
    run();
    return KeyEventResult.handled;
  }

  /// With Ctrl or Cmd held.
  late final Map<LogicalKeyboardKey, _KeyAction> _ctrl = {
    for (final k in [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0])
      k: (_) => _handled(() => _notifier.resetZoom()),
    for (final k in [
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    ])
      k: (_) => _handled(() => _notifier.zoomBy(1.25)),
    for (final k in [LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract])
      k: (_) => _handled(() => _notifier.zoomBy(1 / 1.25)),
    LogicalKeyboardKey.keyZ: (_) => _handled(() {
          if (HardwareKeyboard.instance.isShiftPressed) {
            _notifier.redo();
          } else {
            _notifier.undo();
          }
        }),
    LogicalKeyboardKey.keyY: (_) => _handled(() => _notifier.redo()),
    LogicalKeyboardKey.keyS: (_) => _handled(save),
    LogicalKeyboardKey.keyF: (_) => _handled(openFind),
    LogicalKeyboardKey.keyC: (_) => _copy(),
    LogicalKeyboardKey.keyX: (_) => _cut(),
    LogicalKeyboardKey.keyV: (_) => _handled(() => clipboard.pasteFromClipboard()),
    LogicalKeyboardKey.keyD: (_) => _handled(() => _notifier.duplicateSelection()),
    LogicalKeyboardKey.keyA: (_) => _handled(() => _notifier.selectAll()),
  };

  /// Without Ctrl or Cmd: page navigation and single-key tools.
  late final Map<LogicalKeyboardKey, _KeyAction> _plain = {
    for (final k in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.pageUp])
      k: (_) => _arrow(-1),
    for (final k in [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.pageDown])
      k: (_) => _arrow(1),
    LogicalKeyboardKey.home: (_) => _homeEnd(first: true),
    LogicalKeyboardKey.end: (_) => _homeEnd(first: false),
    LogicalKeyboardKey.keyP: (_) => _handled(() => pickTool(CanvasTool.pen)),
    // E restores the last picked eraser sub-mode (per-stroke or per-area).
    LogicalKeyboardKey.keyE: (_) =>
        _handled(() => pickTool(_notifier.lastEraserMode)),
    LogicalKeyboardKey.keyL: (_) => _handled(() => pickTool(CanvasTool.lasso)),
    LogicalKeyboardKey.keyH: (_) => _handled(() => pickTool(CanvasTool.pan)),
    LogicalKeyboardKey.keyT: (_) => _handled(() => pickTool(CanvasTool.text)),
    LogicalKeyboardKey.keyB: (_) => _handled(() => pickTool(CanvasTool.brush)),
  };

  /// Whatever the modifiers.
  late final Map<LogicalKeyboardKey, _KeyAction> _always = {
    LogicalKeyboardKey.delete: (_) => _delete(),
    LogicalKeyboardKey.backspace: (_) => _delete(),
    LogicalKeyboardKey.escape: (_) => _escape(),
    // ? (Shift+/) opens the shortcut cheat sheet.
    LogicalKeyboardKey.question: (_) => _help(),
    LogicalKeyboardKey.slash: (_) => _help(),
  };

  KeyEventResult _help() {
    if (!HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    showShortcutHelp();
    return KeyEventResult.handled;
  }

  KeyEventResult _copy() {
    final s = ref.read(canvasProvider);
    final notif = _notifier;
    // Lasso selection takes priority; otherwise the single selected element
    // (image / shape / text picked via double-tap).
    if (s?.lassoSelection != null) {
      notif.copySelection();
      // Strokes/text can't go on the system clipboard: make sure a later
      // Ctrl+V uses THIS copy, not a stale leftover image.
      unawaited(clipboard.markSystemImageSeen());
    } else if (s?.selectedElementId != null) {
      final elId = s!.selectedElementId!;
      notif.copyElement(elId);
      // Mirror image bytes to the system clipboard so paste in other apps
      // works; for a non-image element mark any stale system image as seen
      // so Ctrl+V prefers this copy.
      if (clipboard.selectedElementIsImage(s, elId)) {
        unawaited(clipboard.copyImageElementToSystemClipboard(elId));
      } else {
        unawaited(clipboard.markSystemImageSeen());
      }
    } else {
      return KeyEventResult.ignored;
    }
    toast(AppLocalizations.of(context).csSelectionCopied);
    return KeyEventResult.handled;
  }

  KeyEventResult _cut() {
    final s = ref.read(canvasProvider);
    final notif = _notifier;
    if (s?.lassoSelection != null) {
      notif.cutSelection();
    } else if (s?.selectedElementId != null) {
      notif.cutElement(s!.selectedElementId!);
    } else {
      return KeyEventResult.ignored;
    }
    toast(AppLocalizations.of(context).csSelectionCut);
    return KeyEventResult.handled;
  }

  /// Not while typing in a text editor, transforming a lasso, placing a
  /// paste or symbol, or drawing a stroke: those have their own arrow keys.
  bool get _navBlocked {
    final s = ref.read(canvasProvider);
    return s == null ||
        s.pendingSymbol != null ||
        s.pendingPaste ||
        s.activeStroke.isNotEmpty;
  }

  KeyEventResult _arrow(int dir) {
    if (_navBlocked) return KeyEventResult.ignored;
    // Hold-to-accelerate: after ~0.6 s 2 pages per tick, ~1.3 s 3, ~2 s 5.
    final now = DateTime.now();
    final isContinuation = _lastArrowAt != null &&
        _lastArrowDir == dir &&
        now.difference(_lastArrowAt!).inMilliseconds < 220;
    if (!isContinuation) {
      _arrowHoldCount = 0;
    }
    _arrowHoldCount++;
    _lastArrowAt = now;
    _lastArrowDir = dir;
    // Slower ramp than the OS key-repeat so a brief tap stays single-page.
    final step = _arrowHoldCount < 6
        ? 1
        : _arrowHoldCount < 12
            ? 2
            : _arrowHoldCount < 20
                ? 3
                : 5;
    for (int i = 0; i < step; i++) {
      if (dir < 0) {
        _notifier.prevPage();
      } else {
        _notifier.nextPage();
      }
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _homeEnd({required bool first}) {
    if (_navBlocked) return KeyEventResult.ignored;
    final filtered = ref.read(canvasProvider)!.filteredPageIndices;
    if (filtered.isNotEmpty) {
      _notifier.goToPage(first ? filtered.first : filtered.last);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _delete() {
    final state = ref.read(canvasProvider);
    if (state?.selectedElementId != null) {
      _notifier.deleteElement(state!.selectedElementId!);
      return KeyEventResult.handled;
    }
    if (state?.lassoSelection != null) {
      _notifier.deleteSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _escape() {
    // Presentation mode owns the whole screen while active: leave it first.
    if (isPresentationMode()) {
      exitPresentationMode();
      return KeyEventResult.handled;
    }
    if (isPopupOpen()) {
      closePopup();
      return KeyEventResult.handled;
    }
    final state = ref.read(canvasProvider);
    if (state?.pendingSymbol != null) {
      _notifier.clearPendingSymbol();
      return KeyEventResult.handled;
    }
    if (state?.pendingPaste == true) {
      _notifier.cancelPendingPaste();
      return KeyEventResult.handled;
    }
    if (isFindOpen() &&
        state?.selectedElementId == null &&
        state?.lassoSelection == null) {
      closeFind();
      return KeyEventResult.handled;
    }
    _notifier.clearSelection();
    _notifier.deselectElement();
    return KeyEventResult.handled;
  }
}
