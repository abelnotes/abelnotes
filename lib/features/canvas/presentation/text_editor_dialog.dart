// ═══════════════════════════════════════════════════════════════
//  text_editor_dialog.dart
//
//  Rich text editor for canvas TextElements. Per-character styling
//  (bold / italic / underline / strikethrough / color / size) kept in
//  a parallel style list inside RichTextEditingController, spliced on
//  every edit by diffing the text. On confirm the char styles are
//  run-length-encoded into TextSpanData runs for the .ncnote model.
// ═══════════════════════════════════════════════════════════════

import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Unstyled character: all flags off, color/size inherited from the
/// element. Stored with an empty `text` — the controller only uses the
/// style fields; `text` is filled when encoding to spans.
const TextSpanData kPlainCharStyle = TextSpanData(text: '');

bool sameSpanStyle(TextSpanData a, TextSpanData b) =>
    a.bold == b.bold &&
    a.italic == b.italic &&
    a.underline == b.underline &&
    a.strikethrough == b.strikethrough &&
    a.color == b.color &&
    a.fontSize == b.fontSize;

/// Splice [styles] (one entry per char of [oldText]) to track the edit
/// that turned [oldText] into [newText]. Diffs by common prefix/suffix —
/// handles typing, deletes, IME bulk replaces and autocorrect. Inserted
/// chars take [insertStyle], falling back to the style of the char left
/// of the insertion point (how every word processor behaves).
List<TextSpanData> spliceCharStyles(
  String oldText,
  String newText,
  List<TextSpanData> styles, {
  TextSpanData? insertStyle,
}) {
  // Defensive resync if the list ever got out of step.
  if (styles.length != oldText.length) {
    styles = List<TextSpanData>.filled(oldText.length, kPlainCharStyle);
  }
  var p = 0;
  final maxP = min(oldText.length, newText.length);
  while (p < maxP && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
    p++;
  }
  var s = 0;
  final maxS = min(oldText.length - p, newText.length - p);
  while (s < maxS &&
      oldText.codeUnitAt(oldText.length - 1 - s) ==
          newText.codeUnitAt(newText.length - 1 - s)) {
    s++;
  }
  final insertedCount = newText.length - p - s;
  final TextSpanData fill = insertStyle ??
      (p > 0
          ? styles[p - 1]
          : (styles.isNotEmpty ? styles.first : kPlainCharStyle));
  return <TextSpanData>[
    ...styles.take(p),
    ...List<TextSpanData>.filled(insertedCount, fill),
    ...styles.skip(oldText.length - s),
  ];
}

/// Run-length-encode per-char styles + text into TextSpanData runs.
/// Returns an empty list when every char is plain (legacy-compatible:
/// the element renders `content` with its element-level style).
List<TextSpanData> encodeSpans(String text, List<TextSpanData> styles) {
  if (text.isEmpty) return const [];
  if (styles.length != text.length) return const [];
  final allPlain = styles.every((s) => sameSpanStyle(s, kPlainCharStyle));
  if (allPlain) return const [];
  final spans = <TextSpanData>[];
  var runStart = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || !sameSpanStyle(styles[i], styles[runStart])) {
      spans.add(styles[runStart].copyWith(text: text.substring(runStart, i)));
      runStart = i;
    }
  }
  return spans;
}

/// Expand TextSpanData runs back into one style entry per char. Returns
/// null if the spans don't cover [text] exactly (corrupt/foreign data —
/// caller falls back to plain).
List<TextSpanData>? expandSpans(String text, List<TextSpanData> spans) {
  final styles = <TextSpanData>[];
  for (final span in spans) {
    final style = span.copyWith(text: '');
    for (var i = 0; i < span.text.length; i++) {
      styles.add(style);
    }
  }
  if (styles.length != text.length) return null;
  return styles;
}

/// TextEditingController that carries one style per character and keeps
/// it consistent across arbitrary edits (see [spliceCharStyles]).
class RichTextEditingController extends TextEditingController {
  List<TextSpanData> charStyles;

  /// Style applied to the next insertion when the user toggles a style
  /// with a collapsed cursor ("turn bold on, then type"). Cleared on the
  /// insertion itself or when the cursor moves away.
  TextSpanData? _typingStyle;
  int? _typingAnchor;

  RichTextEditingController._(String text, this.charStyles)
      : super(text: text);

  factory RichTextEditingController.fromTextData(TextData? initial) {
    if (initial == null) {
      return RichTextEditingController._('', <TextSpanData>[]);
    }
    final text = initial.content;
    List<TextSpanData>? styles;
    if (initial.spans.isNotEmpty) {
      styles = expandSpans(text, initial.spans);
    }
    // Legacy element-level bold/italic: bake into per-char styles so the
    // editor shows and preserves them.
    styles ??= List<TextSpanData>.filled(
      text.length,
      TextSpanData(text: '', bold: initial.bold, italic: initial.italic),
    );
    return RichTextEditingController._(text, styles);
  }

  @override
  set value(TextEditingValue newValue) {
    final old = value;
    if (newValue.text != old.text) {
      charStyles = spliceCharStyles(old.text, newValue.text, charStyles,
          insertStyle: _typingStyle);
      _typingStyle = null;
      _typingAnchor = null;
    } else if (_typingStyle != null &&
        _typingAnchor != null &&
        newValue.selection.baseOffset != _typingAnchor) {
      _typingStyle = null;
      _typingAnchor = null;
    }
    super.value = newValue;
  }

  /// Style "at the caret": the char before the cursor, or the first char,
  /// or plain. Used to seed collapsed-cursor toggles and the toolbar
  /// active states.
  TextSpanData styleAtCaret() {
    if (_typingStyle != null) return _typingStyle!;
    final sel = selection;
    if (charStyles.isEmpty) return kPlainCharStyle;
    if (!sel.isValid) return charStyles.first;
    final i = sel.isCollapsed ? sel.baseOffset - 1 : sel.start;
    if (i < 0) return charStyles.first;
    if (i >= charStyles.length) return charStyles.last;
    return charStyles[i];
  }

  /// True when EVERY char in the selection satisfies [test] (collapsed
  /// selection → caret style). Drives toggle direction + button states.
  bool selectionAll(bool Function(TextSpanData) test) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed || charStyles.isEmpty) {
      return test(styleAtCaret());
    }
    final a = sel.start.clamp(0, charStyles.length);
    final b = sel.end.clamp(0, charStyles.length);
    if (a >= b) return test(styleAtCaret());
    for (var i = a; i < b; i++) {
      if (!test(charStyles[i])) return false;
    }
    return true;
  }

  /// Apply [f] to the selected range, or set the typing style when the
  /// cursor is collapsed.
  void applyStyle(TextSpanData Function(TextSpanData) f) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      _typingStyle = f(styleAtCaret());
      _typingAnchor = sel.isValid ? sel.baseOffset : null;
      notifyListeners();
      return;
    }
    final a = sel.start.clamp(0, charStyles.length);
    final b = sel.end.clamp(0, charStyles.length);
    for (var i = a; i < b; i++) {
      charStyles[i] = f(charStyles[i]);
    }
    notifyListeners();
  }

  void toggleBold() {
    final on = !selectionAll((s) => s.bold);
    applyStyle((s) => s.copyWith(bold: on));
  }

  void toggleItalic() {
    final on = !selectionAll((s) => s.italic);
    applyStyle((s) => s.copyWith(italic: on));
  }

  void toggleUnderline() {
    final on = !selectionAll((s) => s.underline);
    applyStyle((s) => s.copyWith(underline: on));
  }

  void toggleStrikethrough() {
    final on = !selectionAll((s) => s.strikethrough);
    applyStyle((s) => s.copyWith(strikethrough: on));
  }

  List<TextSpanData> toSpans() => encodeSpans(text, charStyles);

  TextStyle _flutterStyle(TextSpanData s, TextStyle? base) {
    TextDecoration deco = TextDecoration.none;
    if (s.underline && s.strikethrough) {
      deco = TextDecoration.combine(
          [TextDecoration.underline, TextDecoration.lineThrough]);
    } else if (s.underline) {
      deco = TextDecoration.underline;
    } else if (s.strikethrough) {
      deco = TextDecoration.lineThrough;
    }
    return (base ?? const TextStyle()).copyWith(
      fontWeight: s.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
      decoration: deco,
      color: s.color != null ? Color(s.color!) : null,
      fontSize: s.fontSize,
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = text;
    if (t.isEmpty) return TextSpan(style: style);
    if (charStyles.length != t.length) {
      // Defensive resync — never let the field render desynced.
      charStyles = List<TextSpanData>.filled(t.length, kPlainCharStyle);
    }
    final children = <TextSpan>[];
    var runStart = 0;
    for (var i = 1; i <= t.length; i++) {
      if (i == t.length || !sameSpanStyle(charStyles[i], charStyles[runStart])) {
        children.add(TextSpan(
          text: t.substring(runStart, i),
          style: _flutterStyle(charStyles[runStart], style),
        ));
        runStart = i;
      }
    }
    return TextSpan(style: style, children: children);
  }
}

/// What the dialog hands back on confirm.
class TextEditorResult {
  final String content;
  final List<TextSpanData> spans;
  final double fontSize;
  final int color;
  final String alignment;

  const TextEditorResult({
    required this.content,
    required this.spans,
    required this.fontSize,
    required this.color,
    required this.alignment,
  });
}

const List<double> _kFontSizes = [10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48];

const List<int> _kSwatches = [
  0xFF000000,
  0xFF616161,
  0xFFD32F2F,
  0xFFF57C00,
  0xFFFBC02D,
  0xFF388E3C,
  0xFF1976D2,
  0xFF7B1FA2,
];

/// Show the rich text editor. [initial] non-null = edit an existing
/// element (pre-filled); null = new text, with [defaultColor] as base.
/// Returns null on cancel.
Future<TextEditorResult?> showTextEditorDialog(
  BuildContext context, {
  TextData? initial,
  int defaultColor = 0xFF000000,
}) {
  return showDialog<TextEditorResult>(
    context: context,
    builder: (_) =>
        _TextEditorDialog(initial: initial, defaultColor: defaultColor),
  );
}

class _TextEditorDialog extends StatefulWidget {
  final TextData? initial;
  final int defaultColor;
  const _TextEditorDialog({this.initial, required this.defaultColor});

  @override
  State<_TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<_TextEditorDialog> {
  late final RichTextEditingController _controller;
  late double _baseFontSize;
  late int _baseColor;
  late String _alignment;

  @override
  void initState() {
    super.initState();
    _controller = RichTextEditingController.fromTextData(widget.initial);
    _baseFontSize = widget.initial?.fontSize ?? 16.0;
    _baseColor = widget.initial?.color ?? widget.defaultColor;
    _alignment = widget.initial?.alignment ?? 'left';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasRangeSelection {
    final sel = _controller.selection;
    return sel.isValid && !sel.isCollapsed;
  }

  void _setFontSize(double size) {
    if (_hasRangeSelection) {
      // Span override; equal to base → clear the override (inherit).
      final v = size == _baseFontSize ? null : size;
      _controller.applyStyle((s) => s.copyWith(fontSize: v));
    } else {
      setState(() => _baseFontSize = size);
    }
  }

  void _setColor(int color) {
    if (_hasRangeSelection) {
      final v = color == _baseColor ? null : color;
      _controller.applyStyle((s) => s.copyWith(color: v));
    } else {
      setState(() => _baseColor = color);
    }
  }

  void _confirm() {
    final content = _controller.text;
    if (content.trim().isEmpty) {
      Navigator.pop(context); // empty = cancel
      return;
    }
    Navigator.pop(
      context,
      TextEditorResult(
        content: content,
        spans: _controller.toSpans(),
        fontSize: _baseFontSize,
        color: _baseColor,
        alignment: _alignment,
      ),
    );
  }

  Widget _styleToggle({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon,
              size: 19,
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _alignToggle(String value, IconData icon, String tooltip) {
    final cs = Theme.of(context).colorScheme;
    final active = _alignment == value;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _alignment = value),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon,
              size: 19,
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initial == null
          ? l10n.tedInsertTextTitle
          : l10n.tedEditTextTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Toolbar: style toggles + alignment + size ──
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final c = _controller;
                final sizeAtSel = _hasRangeSelection
                    ? (c.styleAtCaret().fontSize ?? _baseFontSize)
                    : _baseFontSize;
                return Wrap(
                  spacing: 2,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _styleToggle(
                      icon: Icons.format_bold,
                      tooltip: l10n.tedBoldTooltip,
                      active: c.selectionAll((s) => s.bold),
                      onTap: c.toggleBold,
                    ),
                    _styleToggle(
                      icon: Icons.format_italic,
                      tooltip: l10n.tedItalicTooltip,
                      active: c.selectionAll((s) => s.italic),
                      onTap: c.toggleItalic,
                    ),
                    _styleToggle(
                      icon: Icons.format_underline,
                      tooltip: l10n.tedUnderlineTooltip,
                      active: c.selectionAll((s) => s.underline),
                      onTap: c.toggleUnderline,
                    ),
                    _styleToggle(
                      icon: Icons.format_strikethrough,
                      tooltip: l10n.tedStrikethroughTooltip,
                      active: c.selectionAll((s) => s.strikethrough),
                      onTap: c.toggleStrikethrough,
                    ),
                    Container(
                        width: 1,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: cs.outlineVariant),
                    _alignToggle('left', Icons.format_align_left, l10n.tedAlignLeft),
                    _alignToggle('center', Icons.format_align_center, l10n.tedAlignCenter),
                    _alignToggle('right', Icons.format_align_right, l10n.tedAlignRight),
                    Container(
                        width: 1,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: cs.outlineVariant),
                    DropdownButton<double>(
                      value: _kFontSizes.contains(sizeAtSel) ? sizeAtSel : null,
                      hint: Text('${sizeAtSel.round()}'),
                      underline: const SizedBox.shrink(),
                      items: _kFontSizes
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text('${s.round()}')))
                          .toList(),
                      onChanged: (s) {
                        if (s != null) _setFontSize(s);
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            // ── Color swatches ──
            Wrap(
              spacing: 6,
              children: [
                for (final c in _kSwatches)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _setColor(c),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _baseColor == c && !_hasRangeSelection
                              ? cs.primary
                              : cs.outlineVariant,
                          width: _baseColor == c && !_hasRangeSelection ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Editor field ──
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyB, control: true):
                    _controller.toggleBold,
                const SingleActivator(LogicalKeyboardKey.keyI, control: true):
                    _controller.toggleItalic,
                const SingleActivator(LogicalKeyboardKey.keyU, control: true):
                    _controller.toggleUnderline,
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _confirm,
              },
              child: TextField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 10,
                // The editor previews the text exactly as it will look on the
                // (white) page: real glyph colours on a paper-white field.
                // Without the fixed light fill, the canvas colours (black by
                // default) sat on the dark dialog surface in dark mode and were
                // unreadable. Cursor/hint are forced dark to stay visible.
                cursorColor: Colors.black54,
                style: TextStyle(
                  fontSize: _baseFontSize.clamp(12, 24),
                  color: Color(_baseColor),
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  // Material blends the theme hoverColor over the fill while the
                  // mouse is over a filled field — in dark mode that tinted the
                  // white back to grey on hover. Kill the hover overlay so the
                  // paper stays white.
                  hoverColor: Colors.transparent,
                  hintText: l10n.tedWriteHereHint,
                  hintStyle: const TextStyle(color: Colors.black38),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.tedCancel)),
        FilledButton(onPressed: _confirm, child: Text(l10n.tedInsert)),
      ],
    );
  }
}
