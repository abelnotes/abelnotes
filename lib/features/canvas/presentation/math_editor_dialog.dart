// LaTeX source editor for a math element, with a live typeset preview.

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

/// Edited LaTeX, or null when cancelled or cleared.
Future<String?> showMathEditorDialog(BuildContext context, {required String initial}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _MathEditorDialog(initial: initial),
  );
}

class _MathEditorDialog extends StatefulWidget {
  final String initial;
  const _MathEditorDialog({required this.initial});

  @override
  State<_MathEditorDialog> createState() => _MathEditorDialogState();
}

class _MathEditorDialogState extends State<_MathEditorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final latex = _controller.text.trim();
    Navigator.pop(context, latex.isEmpty ? null : latex);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.mathEditTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.all(12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => Math.tex(
                    value.text,
                    mathStyle: MathStyle.display,
                    textStyle: TextStyle(fontSize: 26, color: cs.onSurface),
                    onErrorFallback: (_) => Text(l10n.mathEditInvalid,
                        style: TextStyle(color: cs.error)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              // Enter saves; LaTeX never needs a hard line break here.
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.mathEditHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.tedCancel)),
        FilledButton(onPressed: _confirm, child: Text(l10n.csSave)),
      ],
    );
  }
}
