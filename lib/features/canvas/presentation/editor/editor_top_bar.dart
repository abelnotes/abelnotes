// The editor's top bar wired to the notebook: title, page count, undo and
// redo, sync state and the input-mode toggles. Rebuilds only for those.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';

class EditorTopBar extends ConsumerWidget {
  const EditorTopBar({
    super.key,
    required this.center,
    required this.isMobilePlatform,
    required this.onBack,
    required this.onPagesTap,
    required this.onImportFileTap,
    required this.onMoreTap,
    required this.onFindTap,
  });

  /// The tool dock when it lives in the bar, else null.
  final Widget? center;
  final bool isMobilePlatform;
  final VoidCallback onBack;
  final VoidCallback onPagesTap;
  final VoidCallback onImportFileTap;
  final VoidCallback onMoreTap;
  final VoidCallback onFindTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(canvasProvider.notifier);
    final s = ref.watch(canvasProvider.select((s) => s == null
        ? null
        : (
            title: s.metadata.title,
            cover: s.metadata.coverColor,
            page: s.currentPageIndex,
            total: s.document.pages.length,
            dirty: s.isDirty,
            conflict: s.pendingConflicts.isNotEmpty,
            canUndo: s.document.pages.isNotEmpty &&
                s.undoStack.any((e) => e.pageFileName == s.currentPageFileName),
            canRedo: s.document.pages.isNotEmpty &&
                s.redoStack.any((e) => e.pageFileName == s.currentPageFileName),
          )));
    final mouseDraws =
        ref.watch(appSettingsProvider.select((s) => s.mouseDraws));
    final touchDraws =
        !(ref.watch(appSettingsProvider.select((s) => s.stylusOnlyDrawing)) ??
            false);
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([
        notifier.hasSyncFailure,
        notifier.remoteSaveInFlight,
        notifier.keptLocal,
      ]),
      builder: (_, __) {
        // Honest state: conflict > offline > local > pending > ok.
        final HwSyncState syncState;
        if (s.conflict) {
          syncState = HwSyncState.conflict;
        } else if (notifier.hasSyncFailure.value) {
          syncState = HwSyncState.offline;
        } else if (notifier.keptLocal.value) {
          syncState = HwSyncState.localOnly;
        } else if (s.dirty || notifier.remoteSaveInFlight.value) {
          syncState = HwSyncState.pending;
        } else {
          syncState = HwSyncState.ok;
        }
        return HwEditorTopBar(
          notebookTitle: s.title,
          coverColor: Color(s.cover),
          currentPage: s.page + 1,
          totalPages: s.total,
          dirty: s.dirty && !notifier.isPreview,
          canUndo: s.canUndo,
          canRedo: s.canRedo,
          syncState: syncState,
          onBack: onBack,
          onUndo: () => notifier.undo(),
          onRedo: () => notifier.redo(),
          // Scratch notebooks get the pages/chapters UI too.
          showPages: true,
          onPagesTap: onPagesTap,
          onAddPage: () => ref.read(canvasProvider.notifier).addPage(),
          onImportFileTap: onImportFileTap,
          onMoreTap: onMoreTap,
          onFindTap: onFindTap,
          mouseDraws: mouseDraws,
          // No mouse on a touch-only phone/tablet: swap the mouse toggle for
          // a finger-draws-vs-pans one.
          onToggleMouseMode: isMobilePlatform
              ? null
              : () => ref
                  .read(appSettingsProvider.notifier)
                  .setMouseDraws(!mouseDraws),
          touchDraws: touchDraws,
          center: center,
          onToggleTouchDraws: isMobilePlatform
              ? () => ref
                  .read(appSettingsProvider.notifier)
                  .setStylusOnlyDrawing(touchDraws)
              : null,
        );
      },
    );
  }
}
