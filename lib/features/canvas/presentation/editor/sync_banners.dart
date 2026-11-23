// Transient banners over the page about loading and syncing: the pill while a
// remote pull runs and the thin bar while only the opening page is loaded.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// "Syncing..." pill while a remote pull is in flight, so the user knows the
/// notebook may update shortly. Positioned: put it straight in a Stack.
class PullProgressPill extends StatelessWidget {
  const PullProgressPill({
    super.key,
    required this.isPulling,
    required this.progress,
  });

  final ValueListenable<bool> isPulling;
  final ValueListenable<({int done, int total})> progress;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 64,
      right: 12,
      child: ValueListenableBuilder<bool>(
        valueListenable: isPulling,
        builder: (_, pulling, __) => AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: pulling ? 1.0 : 0.0,
          // Only MOUNT the spinner while pulling: an indeterminate indicator
          // runs a Ticker for as long as it is in the tree, even at opacity 0,
          // which pegged the idle editor at 50-99% CPU.
          child: !pulling
              ? const SizedBox.shrink()
              : IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: HwTheme.alphaScrim),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ValueListenableBuilder<({int done, int total})>(
                      valueListenable: progress,
                      builder: (_, progress, __) {
                        final label = progress.total > 0
                            ? AppLocalizations.of(context)
                                .csSyncProgressCount(progress.done, progress.total)
                            : AppLocalizations.of(context).csSyncing;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: progress.total > 0
                                    ? progress.done / progress.total
                                    : null,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Only the opening page is loaded yet: input waits, a thin bar shows it.
/// Positioned: put it straight in a Stack.
class PagesLoadingBar extends StatelessWidget {
  const PagesLoadingBar({super.key, required this.loading});

  final ValueListenable<bool> loading;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ValueListenableBuilder<bool>(
        valueListenable: loading,
        builder: (context, loading, _) => loading
            ? const AbsorbPointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
