// contribute.abelnotes.app: a prompt, a pad to write it on, and the queue of
// what was written (DonationScreen); nothing leaves the browser before Send.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

import '../donation_formula_page.dart';
import '../donation_review_page.dart' show donationSymbolName;
import '../donation_sample.dart';
import '../donation_screen.dart';
import '../donation_store.dart';
import 'guided_prompts.dart';
import 'symbol_glyph.dart';
import 'writing_pad.dart';

class GuidedPage extends ConsumerStatefulWidget {
  const GuidedPage({super.key, this.prompts});

  /// Overridable for tests (a seeded generator).
  final GuidedPrompts? prompts;

  @override
  ConsumerState<GuidedPage> createState() => _GuidedPageState();
}

class _GuidedPageState extends ConsumerState<GuidedPage> {
  late final GuidedPrompts _prompts = widget.prompts ?? GuidedPrompts();
  final _pad = PadController();
  DonationKind _kind = DonationKind.formula;
  late GuidedPrompt _prompt = _nextPrompt();
  double _padWidth = kPadUnits;

  GuidedPrompt _nextPrompt() => _prompts.next(_kind, accept: latexParses);

  @override
  void dispose() {
    _pad.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _setKind(DonationKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _prompt = _nextPrompt();
      _pad.clear();
    });
  }

  void _skip() => setState(() {
        _prompt = _nextPrompt();
        _pad.clear();
      });

  void _next() {
    final n = ref.read(donationProvider.notifier);
    if (!n.hasRoom) {
      _toast(AppLocalizations.of(context).donGuidedFull);
      return;
    }
    final sample = DonationSample.guided(
      id: const Uuid().v4(),
      created: DateTime.now(),
      kind: _prompt.kind,
      strokes: _pad.toUnits(_padWidth),
      label: _prompt.label,
    );
    if (sample != null) n.add(sample);
    _skip();
  }

  void _openQueue() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DonationScreen()));

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final st = ref.watch(donationProvider);
    // A short screen gives the pad the intro's room; the queue screen and
    // the consent say the same before anything is sent.
    final tall = MediaQuery.sizeOf(context).height >= 700;
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                  child: Row(children: [
                    Expanded(
                      child: Text(l10n.donGuidedTitle,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink0)),
                    ),
                    const SizedBox(width: 12),
                    // Long translations shrink the button, never push the title out.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: math.min(MediaQuery.sizeOf(context).width, 760) * 0.5),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: HwButton(
                          label: l10n.donGuidedReview(st.queue.length),
                          style: HwButtonStyle.solid,
                          onPressed: st.loaded ? _openQueue : null,
                        ),
                      ),
                    ),
                  ]),
                ),
                if (tall)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Text(l10n.donGuidedIntro, style: TextStyle(fontSize: 13, color: p.ink2, height: 1.45)),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, tall ? 0 : 4, 20, tall ? 0 : 4),
                  child: const DonationPrivacyLink(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _KindPicker(kind: _kind, onChanged: _setKind),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _PromptCard(prompt: _prompt),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    constraints: const BoxConstraints(minHeight: 140),
                    decoration: BoxDecoration(
                      color: p.paper0,
                      borderRadius: BorderRadius.circular(HwTheme.rLg),
                      border: Border.all(color: p.paper3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(builder: (ctx, c) {
                      _padWidth = c.maxWidth;
                      return WritingPad(
                        key: const ValueKey('pad'),
                        controller: _pad,
                        color: p.ink0,
                        hint: l10n.donGuidedPadHint,
                        guide: _kind == DonationKind.formula ? p.paper2 : null,
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
                  child: ListenableBuilder(
                    listenable: _pad,
                    builder: (context, _) => Row(children: [
                      IconButton(
                        tooltip: l10n.donGuidedUndo,
                        icon: HwIcon('undo', size: 18, color: _pad.isEmpty ? p.ink3 : p.ink1),
                        onPressed: _pad.isEmpty ? null : _pad.undo,
                      ),
                      IconButton(
                        tooltip: l10n.donGuidedClear,
                        icon: HwIcon('trash', size: 18, color: _pad.isEmpty ? p.ink3 : p.ink1),
                        onPressed: _pad.isEmpty ? null : _pad.clear,
                      ),
                      const Spacer(),
                      HwButton(label: l10n.donGuidedSkip, onPressed: _skip),
                      const SizedBox(width: 8),
                      HwButton(
                        label: l10n.donGuidedNext,
                        style: HwButtonStyle.primary,
                        onPressed: _pad.isEmpty || !st.loaded ? null : _next,
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formulas or circuit symbols, styled like the theme picker in Settings.
class _KindPicker extends StatelessWidget {
  const _KindPicker({required this.kind, required this.onChanged});
  final DonationKind kind;
  final ValueChanged<DonationKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(children: [
      for (final (k, label) in [
        (DonationKind.formula, l10n.donGuidedFormulas),
        (DonationKind.circuit, l10n.donGuidedCircuits),
      ]) ...[
        if (k != DonationKind.formula) const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            selected: k == kind,
            child: GestureDetector(
              onTap: () => onChanged(k),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: k == kind ? p.accentSoft : p.paper0,
                  borderRadius: BorderRadius.circular(HwTheme.rMd),
                  border: Border.all(color: k == kind ? p.accent : p.paper2, width: k == kind ? 1.5 : 1),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: k == kind ? p.accentDeep : p.ink1)),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt});
  final GuidedPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final formula = prompt.kind == DonationKind.formula;
    final eyebrow = formula
        ? l10n.donGuidedWriteFormula
        : prompt.label == 'text'
            ? l10n.donGuidedWriteText
            : l10n.donGuidedDrawSymbol;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: p.paper0,
        borderRadius: BorderRadius.circular(HwTheme.rLg),
        border: Border.all(color: p.paper2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(eyebrow.toUpperCase(), style: HwType.eyebrow.copyWith(color: p.ink2)),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: formula
              ? Center(child: FormulaPreview(prompt.label, fontSize: 30, key: ValueKey(prompt.label)))
              : Row(children: [
                  SizedBox(
                    width: 150,
                    height: 88,
                    child: CustomPaint(painter: SymbolGlyphPainter(prompt.label, p.ink0, text: prompt.text)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(donationSymbolName(l10n, prompt.label),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink0)),
                  ),
                ]),
        ),
      ]),
    );
  }
}
