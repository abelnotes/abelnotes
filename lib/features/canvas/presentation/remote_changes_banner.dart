import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// A slim animated banner that slides in from the top when remote changes
/// are detected. Tapping it opens a detail sheet where the user can see
/// per-page diffs and navigate directly to changed pages.
class RemoteChangesBanner extends ConsumerWidget {
  const RemoteChangesBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(
      canvasProvider.select((s) => s?.pendingRemoteChanges),
    );
    if (pending == null) return const SizedBox.shrink();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: _AnimatedBanner(pending: pending),
    );
  }
}

class _AnimatedBanner extends ConsumerStatefulWidget {
  final PendingRemoteChanges pending;
  const _AnimatedBanner({required this.pending});

  @override
  ConsumerState<_AnimatedBanner> createState() => _AnimatedBannerState();
}

class _AnimatedBannerState extends ConsumerState<_AnimatedBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RemoteChangesSheet(pending: widget.pending, ref: ref),
    );
  }

  void _dismiss() {
    ref.read(canvasProvider.notifier).dismissRemoteChanges();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = widget.pending;
    final palette = HwThemeScope.of(context);
    final summary = _buildSummaryText(l10n, p);

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          color: palette.paper2,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _showDetails,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 360;
                  return Row(
                    children: [
                      Icon(Icons.sync, color: palette.ink2, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.rcbBannerTitle,
                              style: TextStyle(
                                color: palette.ink0,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              summary,
                              style: TextStyle(
                                color: palette.ink2,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (compact)
                        // On narrow screens collapse the two chips into a
                        // single trailing button that opens the same sheet.
                        IconButton(
                          onPressed: _showDetails,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.chevron_right, color: palette.ink1),
                          tooltip: l10n.rcbSeeDetails,
                        )
                      else ...[
                        _ActionChip(
                          label: l10n.rcbSeeDetails,
                          color: palette.accent,
                          onTap: _showDetails,
                        ),
                        const SizedBox(width: 6),
                        _ActionChip(
                          label: l10n.rcbDismiss,
                          color: palette.ink0.withValues(alpha: HwTheme.alphaStrong),
                          onTap: _dismiss,
                        ),
                      ],
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

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: p.paper0,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Detail Bottom Sheet ──────────────────────────────────────

class _RemoteChangesSheet extends StatelessWidget {
  final PendingRemoteChanges pending;
  final WidgetRef ref;

  const _RemoteChangesSheet({required this.pending, required this.ref});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.65;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: p.paper1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ──
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.ink0.withValues(alpha: HwTheme.alphaStrong),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: HwTheme.alphaMedium),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.devices, color: p.accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.rcbIncomingChanges,
                      style: TextStyle(
                        color: p.ink0,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.rcbTapPageHint,
                      style: TextStyle(
                        color: p.ink2,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Summary counts ──
          if (pending.newAssetCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.image_outlined, color: HwTheme.teal, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.rcbNewImagesCount(pending.newAssetCount),
                    style: TextStyle(color: p.ink2, fontSize: 13),
                  ),
                ],
              ),
            ),

          // ── Per-page change list ──
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: pending.changedPages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final detail = pending.changedPages[index];
                return _PageChangeCard(
                  detail: detail,
                  onTap: () {
                    ref.read(canvasProvider.notifier).acceptAndGoToPage(detail.pageIndex);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── Action buttons ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(canvasProvider.notifier).dismissRemoteChanges();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.ink1,
                    side: BorderSide(
                      color: p.ink0.withValues(alpha: HwTheme.alphaStrong),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(l10n.rcbKeepMine),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(canvasProvider.notifier).acceptRemoteChanges();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(l10n.rcbApplyAll),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HwTheme.syncOk,
                    foregroundColor: p.paper0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Per-page change card ─────────────────────────────────────

class _PageChangeCard extends StatelessWidget {
  final PageChangeDetail detail;
  final VoidCallback onTap;

  const _PageChangeCard({required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    final isNew = detail.changeType == PageChangeType.added;
    final badgeColor = isNew ? HwTheme.syncOk : HwTheme.syncPending;
    final badgeLabel = isNew ? l10n.rcbBadgeNew : l10n.rcbBadgeModified;
    final badgeIcon = isNew ? Icons.add_circle_outline : Icons.edit_note;

    return Material(
      color: p.ink0.withValues(alpha: HwTheme.alphaLight),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Page number square
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: HwTheme.alphaMedium),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${detail.pageNumber}',
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Page info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row: "Pagina 3" + chapter badge
                    Row(
                      children: [
                        Text(
                          l10n.rcbPageTitle(detail.pageNumber),
                          style: TextStyle(
                            color: p.ink0,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (detail.chapterName != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: HwTheme.alphaStrong),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              detail.chapterName!,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Element diff summary
                    if (detail.hasElementDiff)
                      _ElementDiffRow(detail: detail)
                    else
                      Row(
                        children: [
                          Icon(badgeIcon, color: badgeColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            badgeLabel,
                            style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // Navigate arrow
              Icon(Icons.chevron_right, color: p.ink3, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Element diff summary for a page ──────────────────────────

class _ElementDiffRow extends StatelessWidget {
  final PageChangeDetail detail;
  const _ElementDiffRow({required this.detail});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final diffs = <Widget>[];

    void addDiff(IconData icon, int local, int remote) {
      final delta = remote - local;
      if (delta == 0) return;
      final color = delta > 0 ? HwTheme.syncOk : HwTheme.syncConflict;
      final sign = delta > 0 ? '+' : '';
      diffs.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: p.ink3, size: 13),
            const SizedBox(width: 2),
            Text(
              '$sign$delta',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    addDiff(Icons.gesture, detail.localStrokeCount, detail.remoteStrokeCount);
    addDiff(Icons.image_outlined, detail.localImageCount, detail.remoteImageCount);
    addDiff(Icons.crop_square, detail.localShapeCount, detail.remoteShapeCount);
    addDiff(Icons.text_fields, detail.localTextCount, detail.remoteTextCount);

    if (diffs.isEmpty) {
      return Text(
        AppLocalizations.of(context).rcbContentUpdated,
        style: TextStyle(color: p.ink3, fontSize: 11),
      );
    }

    return Wrap(
      spacing: 10,
      children: diffs,
    );
  }
}

String _buildSummaryText(AppLocalizations l10n, PendingRemoteChanges p) {
  final parts = <String>[];
  if (p.modifiedPageCount > 0) {
    parts.add(l10n.rcbSummaryModifiedPages(p.modifiedPageCount));
  }
  if (p.newPageCount > 0) {
    parts.add(l10n.rcbSummaryNewPages(p.newPageCount));
  }
  if (p.newAssetCount > 0) {
    parts.add(l10n.rcbSummaryImages(p.newAssetCount));
  }
  return parts.isEmpty ? l10n.rcbChangesDetected : parts.join(' · ');
}
