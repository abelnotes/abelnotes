// The donation queue: samples to review, the send, and receipts of past sends.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/primitives/scrollable_sheet.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

import 'donation_client.dart';
import 'donation_formula_page.dart';
import 'donation_review_page.dart';
import 'donation_sample.dart';
import 'donation_store.dart';

const String kPrivacyUrl = 'https://abelnotes.app/privacy#donation';

String donationErrorText(AppLocalizations l, DonationError e) => switch (e) {
      DonationError.offline => l.donErrOffline,
      DonationError.busy => l.donErrBusy,
      DonationError.fullToday => l.donErrFull,
      DonationError.refused => l.donErrRefused,
      DonationError.notFound => l.donErrNotFound,
      DonationError.server => l.donErrServer,
    };

class DonationScreen extends ConsumerStatefulWidget {
  const DonationScreen({super.key});

  @override
  ConsumerState<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends ConsumerState<DonationScreen> {
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final n = ref.read(donationProvider.notifier);
    n.ready.then((_) {
      if (mounted && ref.read(donationProvider).receipts.isNotEmpty) n.refreshReceipts();
    });
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final n = ref.read(donationProvider.notifier);
    final consent = ref.read(donationProvider).consent;
    if (consent == null || consent.version != kDonationConsentVersion) {
      final republish = await showConsentSheet(context, ref.read(donationProvider).reviewed);
      if (republish == null || !mounted) return;
      n.giveConsent(republish: republish);
    }
    setState(() => _sending = true);
    try {
      final sent = await n.sendReviewed();
      if (mounted) _toast(l10n.donSent(sent));
    } on DonationException catch (e) {
      if (mounted) _toast(donationErrorText(l10n, e.error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(DonationReceipt r) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.donDeleteTitle),
        content: Text(l10n.donDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.setCancel)),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: HwTheme.syncConflict),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.donDelete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(donationProvider.notifier).deleteDonation(r.code);
      if (mounted) _toast(l10n.donDeleted);
    } on DonationException catch (e) {
      if (mounted) _toast(donationErrorText(l10n, e.error));
    }
  }

  Future<void> _withdraw() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.donWithdrawTitle),
        content: Text(l10n.donWithdrawBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.setCancel)),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: HwTheme.syncConflict),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.donWithdraw)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ref.read(donationProvider.notifier).withdrawConsent();
    if (mounted) _toast(r.failed == 0 ? l10n.donWithdrawn(r.deleted) : l10n.donWithdrawFailed(r.failed));
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final st = ref.watch(donationProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.yMMMd(locale);
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        // Header, list and send bar share one column, so their edges line up.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                  child: Row(children: [
                    IconButton(
                      icon: const HwIcon('chevron-left', size: 18),
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(l10n.donScreenTitle,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink0)),
                    ),
                  ]),
                ),
                Expanded(
                  child: !st.loaded
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          children: [
                            Text(l10n.donScreenIntro, style: TextStyle(fontSize: 14, color: p.ink2, height: 1.5)),
                            const DonationPrivacyLink(),
                            const SizedBox(height: 8),
                            if (st.queue.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                child: Text(l10n.donEmptyGuided,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 14, color: p.ink2, height: 1.5)),
                              )
                            else
                              _SampleGrid(samples: st.queue),
                            if (st.receipts.isNotEmpty || st.consent != null) ...[
                              const SizedBox(height: 28),
                              Text(l10n.donSentHeader.toUpperCase(), style: HwType.eyebrow.copyWith(color: p.ink2)),
                              const SizedBox(height: 8),
                              if (st.receipts.isNotEmpty) ...[
                                Text(l10n.donAcceptedTotal(st.accepted),
                                    style: TextStyle(fontSize: 14, color: p.ink0, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(l10n.donKeepCode, style: TextStyle(fontSize: 12, color: p.ink2, height: 1.5)),
                                const SizedBox(height: 4),
                                for (final r in st.receipts) _ReceiptRow(r, date, onDelete: () => _delete(r)),
                              ],
                              if (st.consent != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Row(children: [
                                    Expanded(
                                      child: Text(
                                          st.consent!.republish
                                              ? l10n.donConsentGivenRepublish(date.format(st.consent!.given))
                                              : l10n.donConsentGiven(date.format(st.consent!.given)),
                                          style: TextStyle(fontSize: 12, color: p.ink2, height: 1.5)),
                                    ),
                                    HwButton(label: l10n.donWithdraw, onPressed: _withdraw),
                                  ]),
                                ),
                            ],
                          ],
                        ),
                ),
                if (st.queue.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: p.paper2))),
                    child: Row(children: [
                      Expanded(
                        child: Text(l10n.donQueueSummary(st.toReview, st.reviewed),
                            style: TextStyle(fontSize: 13, color: p.ink2)),
                      ),
                      const SizedBox(width: 12),
                      _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : HwButton(
                              label: l10n.donSendCount(st.reviewed),
                              style: HwButtonStyle.primary,
                              onPressed: st.reviewed == 0 ? null : _send,
                            ),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the privacy policy; flush with the text above it.
class DonationPrivacyLink extends StatelessWidget {
  const DonationPrivacyLink({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => launchUrl(Uri.parse(kPrivacyUrl), mode: LaunchMode.externalApplication),
            child: Text(AppLocalizations.of(context).donPrivacy),
          ),
        ),
      );
}

class _SampleGrid extends StatelessWidget {
  const _SampleGrid({required this.samples});
  final List<DonationSample> samples;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(builder: (ctx, c) {
      final cols = (c.maxWidth / 200).floor().clamp(2, 4);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final s in samples)
            SizedBox(
              width: w,
              child: Material(
                color: p.paper0,
                borderRadius: BorderRadius.circular(HwTheme.rMd),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          s.isFormula ? FormulaReviewPage(sampleId: s.id) : DonationReviewPage(sampleId: s.id))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The state sits on the drawing, so a narrow tile
                      // never wraps it against the part count.
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Stack(children: [
                          Positioned.fill(child: CustomPaint(painter: SamplePainter(s, p, l10n, labels: false))),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: HwPill(
                              label: s.sendable ? l10n.donReviewed : l10n.donToReviewShort,
                              background: s.sendable
                                  ? Color.alphaBlend(HwTheme.syncOk.withValues(alpha: 0.18), p.paper0)
                                  : p.accentSoft,
                              foreground: s.sendable ? HwTheme.syncOk : p.accentDeep,
                            ),
                          ),
                        ]),
                      ),
                      // Same height for both kinds, so a mixed grid stays aligned.
                      SizedBox(
                        height: 34,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                          child: s.isFormula
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: s.labelled
                                      ? FormulaPreview(s.latex, fontSize: 14, color: p.ink1)
                                      : Text(l10n.donLatexEmpty, style: TextStyle(fontSize: 12, color: p.ink2)))
                              : Text(l10n.donParts(s.parts.length),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: p.ink2)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow(this.r, this.date, {required this.onDelete});
  final DonationReceipt r;
  final DateFormat date;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final status = switch (r.status) {
      'accepted' => l10n.donStatusAccepted(r.accepted),
      'rejected' => l10n.donStatusRejected,
      'in_review' => l10n.donStatusInReview,
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.paper2))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(r.code,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink0,
                    letterSpacing: 1,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text([date.format(r.sent), l10n.donSamples(r.samples), if (status != null) status].join(' · '),
                style: TextStyle(fontSize: 12, color: p.ink2)),
          ]),
        ),
        IconButton(
          tooltip: l10n.donCopyCode,
          icon: HwIcon('copy', size: 16, color: p.ink1),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: r.code));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(l10n.donCodeCopied)));
          },
        ),
        IconButton(
          tooltip: l10n.donDelete,
          icon: const HwIcon('trash', size: 16, color: HwTheme.syncConflict),
          onPressed: onDelete,
        ),
      ]),
    );
  }
}

/// Consent before a first send. Returns the republish choice, or null when
/// the person did not agree.
Future<bool?> showConsentSheet(BuildContext context, int count) {
  return showScrollableSheet<bool>(
    context: context,
    backgroundColor: HwThemeScope.of(context).paper0,
    builder: (ctx) => _ConsentSheet(count: count),
  );
}

class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet({required this.count});
  final int count;

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool _train = false, _age = false, _republish = false;

  Widget _box(String text, bool value, ValueChanged<bool> onChanged, {String? note}) {
    final p = HwThemeScope.of(context);
    return CheckboxListTile(
      value: value,
      onChanged: (v) => setState(() => onChanged(v ?? false)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(text, style: TextStyle(fontSize: 14, color: p.ink0, height: 1.4)),
      subtitle: note == null ? null : Text(note, style: TextStyle(fontSize: 12, color: p.ink2, height: 1.4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final body = TextStyle(fontSize: 14, color: p.ink1, height: 1.5);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.donConsentTitle, style: HwType.title.copyWith(color: p.ink0)),
            const SizedBox(height: 12),
            Text(l10n.donConsentWhat, style: body),
            const SizedBox(height: 8),
            Text(l10n.donConsentWhy, style: body),
            const SizedBox(height: 8),
            Text(l10n.donConsentReceipt, style: body),
            const SizedBox(height: 8),
            Text(l10n.donConsentController, style: body),
            const DonationPrivacyLink(),
            _box(l10n.donConsentTrain, _train, (v) => _train = v),
            _box(l10n.donConsentAge, _age, (v) => _age = v),
            _box(l10n.donConsentRepublish, _republish, (v) => _republish = v, note: l10n.donConsentRepublishNote),
            const SizedBox(height: 16),
            Row(children: [
              const Spacer(),
              HwButton(label: l10n.setCancel, onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              HwButton(
                label: l10n.donSendCount(widget.count),
                style: HwButtonStyle.primary,
                onPressed: _train && _age ? () => Navigator.pop(context, _republish) : null,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
