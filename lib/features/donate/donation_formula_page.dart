// Reviewing one kept formula: the ink above the LaTeX it stands for, which the
// reviewer edits while a preview shows how it reads.

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

import 'donation_review_page.dart' show SamplePainter;
import 'donation_sample.dart';
import 'donation_store.dart';

/// Whether flutter_math can typeset [latex]: what the preview shows is what
/// the label means.
bool latexParses(String latex) {
  try {
    TexParser(latex, const TexParserSettings()).parse();
    return true;
  } catch (_) {
    return false;
  }
}

String latexProblemText(AppLocalizations l, LatexProblem p) => switch (p) {
      LatexProblem.empty => l.donLatexEmpty,
      LatexProblem.tooLong => l.donLatexTooLong,
      LatexProblem.notAscii => l.donLatexNotAscii,
    };

/// [latex] typeset, scaled down to fit; the source in monospace when it does
/// not parse.
class FormulaPreview extends StatelessWidget {
  const FormulaPreview(this.latex, {super.key, this.fontSize = 22, this.color});
  final String latex;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HwThemeScope.of(context).ink0;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Math.tex(
        latex,
        mathStyle: MathStyle.display,
        textStyle: TextStyle(fontSize: fontSize, color: c),
        onErrorFallback: (_) =>
            Text(latex, style: TextStyle(fontSize: fontSize * 0.7, color: c, fontFamily: 'monospace')),
      ),
    );
  }
}

class FormulaReviewPage extends ConsumerStatefulWidget {
  const FormulaReviewPage({super.key, required this.sampleId});
  final String sampleId;

  @override
  ConsumerState<FormulaReviewPage> createState() => _FormulaReviewPageState();
}

class _FormulaReviewPageState extends ConsumerState<FormulaReviewPage> {
  DonationSample? _sample;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sample = ref.read(donationProvider).queue.where((s) => s.id == widget.sampleId).firstOrNull;
    _text.text = _sample?.latex ?? '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The receiver takes one line of printable ASCII.
  String get _latex => _text.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  void _changed(String _) {
    final s = _sample!.copyWith(latex: _latex, reviewed: false);
    setState(() => _sample = s);
    ref.read(donationProvider.notifier).update(s);
  }

  void _reset() {
    _text.text = _sample!.prompt ?? '';
    _changed(_text.text);
  }

  void _discard() {
    ref.read(donationProvider.notifier).remove(widget.sampleId);
    Navigator.of(context).pop();
  }

  void _markReviewed() {
    ref.read(donationProvider.notifier).update(_sample!.copyWith(latex: _latex, reviewed: true));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final s = _sample;
    if (s == null) return Scaffold(backgroundColor: p.paper1);
    final problem = latexProblem(_latex);
    final parses = problem == null && latexParses(_latex);
    final error = problem != null ? latexProblemText(l10n, problem) : (parses ? null : l10n.donLatexInvalid);
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(children: [
                    IconButton(
                      icon: const HwIcon('chevron-left', size: 18),
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(l10n.donReviewTitle,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink0)),
                    ),
                    if (s.corrections > 0) HwButton(label: l10n.donReset, onPressed: _reset),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Text(l10n.donFormulaHintGuided,
                      style: TextStyle(fontSize: 13, color: p.ink2, height: 1.4)),
                ),
                // The ink gives way to the keyboard, the field and preview stay.
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    constraints: const BoxConstraints(minHeight: 80),
                    decoration: BoxDecoration(
                      color: p.paper0,
                      borderRadius: BorderRadius.circular(HwTheme.rLg),
                      border: Border.all(color: p.paper2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CustomPaint(painter: SamplePainter(s, p, l10n)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.paper0,
                      borderRadius: BorderRadius.circular(HwTheme.rMd),
                      border: Border.all(color: p.paper2),
                    ),
                    alignment: Alignment.center,
                    child: parses ? FormulaPreview(_latex) : const SizedBox.shrink(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    key: const ValueKey('latex'),
                    controller: _text,
                    onChanged: _changed,
                    minLines: 1,
                    maxLines: 3,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.text,
                    style: TextStyle(fontSize: 15, color: p.ink0, fontFamily: HwTheme.fontMono),
                    decoration: InputDecoration(
                      hintText: l10n.donLatexLabel,
                      errorText: error,
                      isDense: true,
                      filled: true,
                      fillColor: p.paper2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(HwTheme.rMd),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(children: [
                    HwButton(label: l10n.donDiscard, color: HwTheme.syncConflict, onPressed: _discard),
                    const Spacer(),
                    HwButton(
                      label: l10n.donMarkReviewed,
                      style: HwButtonStyle.primary,
                      onPressed: parses ? _markReviewed : null,
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
