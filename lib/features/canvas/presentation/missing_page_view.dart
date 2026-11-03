import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

enum _Status { checking, downloading, unreachable, gone, noServer }

/// Shown in place of the canvas when the current page's data isn't on this
/// device. It asks the server first and keeps retrying; replacing or
/// deleting is offered only for a page the server confirms it doesn't have.
class MissingPageView extends ConsumerStatefulWidget {
  const MissingPageView({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  ConsumerState<MissingPageView> createState() => _MissingPageViewState();
}

class _MissingPageViewState extends ConsumerState<MissingPageView> {
  _Status _status = _Status.checking;
  Set<String> _gone = const {};
  Timer? _retry;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  String? get _currentFile {
    final s = ref.read(canvasProvider);
    if (s == null) return null;
    final i = s.currentPageIndex;
    if (i < 0 || i >= s.document.pages.length) return null;
    return s.document.pages[i].fileName;
  }

  Future<void> _check({bool silent = false}) async {
    _retry?.cancel();
    if (_busy) return;
    _busy = true;
    if (!silent) setState(() => _status = _Status.checking);
    final r = await ref.read(canvasProvider.notifier).checkMissingPages();
    _busy = false;
    if (!mounted) return;
    final fn = _currentFile;
    setState(() {
      _gone = r.goneFromServer;
      if (r.noServer) {
        _status = _Status.noServer;
      } else if (!r.reachable) {
        _status = _Status.unreachable;
      } else if (fn != null && r.goneFromServer.contains(fn)) {
        _status = _Status.gone;
      } else {
        _status = _Status.downloading;
      }
    });
    // Keep trying while the page may still arrive; the canvas replaces this
    // view as soon as it does.
    if (_status == _Status.downloading || _status == _Status.unreachable) {
      _retry = Timer(const Duration(seconds: 8), () => _check(silent: true));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.csCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HwTheme.syncConflict),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _replaceWithBlank({required bool all}) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final count = all ? _gone.length : 1;
    if (!await _confirm(
      l10n.csMissingReplaceConfirmTitle(count),
      l10n.csMissingReplaceConfirmBody(count),
      l10n.csMissingReplaceAction,
    )) {
      return;
    }
    // The page may have arrived and replaced this view while the dialog was up.
    if (!mounted) return;
    // Re-check right before writing: the page may have reappeared.
    final r = await ref.read(canvasProvider.notifier).checkMissingPages();
    if (!mounted) return;
    if (!r.noServer && !r.reachable) {
      await _check();
      return;
    }
    final n = ref.read(canvasProvider.notifier);
    final s = ref.read(canvasProvider);
    if (s == null) return;
    final repaired = all
        ? n.repairAllMissingPages(r.goneFromServer)
        : (n.repairMissingPageData(s.currentPageIndex, r.goneFromServer) ? 1 : 0);
    if (repaired == 0) {
      await _check();
      return;
    }
    await n.save();
    messenger.showSnackBar(SnackBar(content: Text(l10n.csPagesRestoredBlank(repaired))));
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      l10n.csMissingDeleteConfirmTitle,
      l10n.csMissingDeleteConfirmBody,
      l10n.csDeletePage,
    )) {
      return;
    }
    if (!mounted) return;
    final s = ref.read(canvasProvider);
    if (s == null) return;
    ref.read(canvasProvider.notifier).deletePage(s.currentPageIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    final s = ref.watch(canvasProvider);
    final index = s?.currentPageIndex ?? 0;
    final pageNo = index + 1;

    final (IconData icon, Color color, String title, String body) = switch (_status) {
      _Status.checking || _Status.downloading => (
          Icons.cloud_download_outlined,
          HwTheme.syncPending,
          l10n.csMissingDownloadingTitle(pageNo),
          l10n.csMissingDownloadingBody,
        ),
      _Status.unreachable => (
          Icons.cloud_off_outlined,
          HwTheme.syncPending,
          l10n.csMissingOfflineTitle(pageNo),
          l10n.csMissingOfflineBody,
        ),
      _Status.gone => (
          Icons.warning_amber_rounded,
          HwTheme.syncConflict,
          l10n.csMissingGoneTitle(pageNo),
          l10n.csMissingGoneBody,
        ),
      _Status.noServer => (
          Icons.warning_amber_rounded,
          HwTheme.syncConflict,
          l10n.csMissingGoneTitle(pageNo),
          l10n.csMissingNoServerBody,
        ),
    };
    final destructive = _status == _Status.gone || _status == _Status.noServer;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: color),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center, style: TextStyle(color: p.ink2)),
                if (_status == _Status.checking || _status == _Status.downloading) ...[
                  const SizedBox(height: 20),
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (index > 0)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.chevron_left),
                        label: Text(l10n.csMissingPreviousPage),
                        onPressed: () => ref.read(canvasProvider.notifier).goToPage(index - 1),
                      ),
                    if (_status != _Status.noServer)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.csRetrySync),
                        onPressed: _status == _Status.checking ? null : _check,
                      ),
                  ],
                ),
                if (destructive) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(l10n.csMissingLastResort, textAlign: TextAlign.center, style: TextStyle(color: p.ink2, fontSize: 13)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l10n.csDeletePage),
                        onPressed: _delete,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.note_add_outlined),
                        label: Text(l10n.csMissingReplaceAction),
                        onPressed: () => _replaceWithBlank(all: false),
                      ),
                      if (_gone.length > 1)
                        TextButton.icon(
                          icon: const Icon(Icons.note_add_outlined),
                          label: Text(l10n.csMissingReplaceAll(_gone.length)),
                          onPressed: () => _replaceWithBlank(all: true),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
