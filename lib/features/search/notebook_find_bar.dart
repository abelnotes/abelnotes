import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/notebook_find.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/primitives/hw_glass.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// A library search hit being opened: the editor shows its words found.
final pendingFindProvider =
    StateProvider<({String notebookId, String query})?>((_) => null);

/// Find-in-notebook state of one editor.
class NotebookFindController extends ChangeNotifier {
  bool _open = false;
  String _query = '';
  List<FindMatch> _matches = const [];
  int _current = -1;
  DocumentStructure? _doc;
  Map<String, PageData>? _pages;
  Map<String, List<InkLine>> _ink = const {};
  Set<int>? _pagesWithMatches;
  PageData? _rectsPage;
  final _rects = <FindMatch, List<Rect>>{};

  bool get isOpen => _open;
  String get query => _query;
  List<FindMatch> get matches => _matches;
  int get current => _current;
  FindMatch? get currentMatch =>
      _current >= 0 && _current < _matches.length ? _matches[_current] : null;

  /// Page indices holding at least one match.
  Set<int> get pagesWithMatches =>
      _pagesWithMatches ??= {for (final m in _matches) m.pageIndex};

  void open() {
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    _open = false;
    _query = '';
    _setMatches(const []);
    _current = -1;
    notifyListeners();
  }

  /// New query; the current match is the first one from [fromPage] on.
  void setQuery(String query, DocumentStructure doc,
      Map<String, PageData> pages, int fromPage) {
    _query = query;
    _doc = doc;
    _pages = pages;
    _setMatches(findInNotebook(doc, pages, query, ink: _ink));
    final i = _matches.indexWhere((m) => m.pageIndex >= fromPage);
    _current = _matches.isEmpty ? -1 : (i < 0 ? 0 : i);
    notifyListeners();
  }

  /// Follows edits; keeps the current match when it is still there. Silent:
  /// called while building.
  void sync(DocumentStructure doc, Map<String, PageData> pages) {
    if (identical(doc, _doc) && identical(pages, _pages)) return;
    _doc = doc;
    _pages = pages;
    if (_query.isEmpty) return;
    final keep = currentMatch;
    _setMatches(findInNotebook(doc, pages, _query, ink: _ink));
    if (_matches.isEmpty) {
      _current = -1;
    } else if (keep == null) {
      _current = 0;
    } else {
      final same = _matches.indexOf(keep);
      final next = _matches.indexWhere((m) => m.pageIndex >= keep.pageIndex);
      _current = same >= 0 ? same : (next >= 0 ? next : _matches.length - 1);
    }
  }

  /// Recognised handwriting of the open notebook, per page file (from the
  /// search index). Re-runs the query when it changes.
  /// Returns true when the current match moved (the caller reveals it).
  bool setInk(Map<String, List<InkLine>> ink, {int fromPage = 0}) {
    _ink = ink;
    final doc = _doc, pages = _pages;
    if (doc == null || pages == null || _query.isEmpty) return false;
    final keep = currentMatch;
    _setMatches(findInNotebook(doc, pages, _query, ink: ink));
    final same = keep == null ? -1 : _matches.indexOf(keep);
    if (same >= 0) {
      _current = same;
    } else {
      final i = _matches.indexWhere((m) => m.pageIndex >= fromPage);
      _current = _matches.isEmpty ? -1 : (i < 0 ? 0 : i);
    }
    notifyListeners();
    return same < 0 && _current >= 0;
  }

  void step(int by) {
    if (_matches.isEmpty) return;
    _current = (_current + by) % _matches.length;
    if (_current < 0) _current += _matches.length;
    notifyListeners();
  }

  /// [m]'s rectangles on [page] (page points), laid out once per page state.
  List<Rect> rectsOf(PageData page, FindMatch m) {
    if (!identical(page, _rectsPage)) {
      _rects.clear();
      _rectsPage = page;
    }
    final file = _doc != null && m.pageIndex < _doc!.pages.length
        ? _doc!.pages[m.pageIndex].fileName
        : null;
    return _rects[m] ??=
        findMatchRects(page, m, ink: _ink[file] ?? const <InkLine>[]);
  }

  void _setMatches(List<FindMatch> m) {
    _matches = m;
    _pagesWithMatches = null;
    _rects.clear();
  }
}

/// The find field floating over the page: query, position, previous/next.
class NotebookFindBar extends StatelessWidget {
  final NotebookFindController controller;
  final TextEditingController text;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  /// A tap anywhere but the bar while the field has focus.
  final VoidCallback onTapOutside;

  const NotebookFindBar({
    super.key,
    required this.controller,
    required this.text,
    required this.focus,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.onTapOutside,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final total = controller.matches.length;
    final hasQuery = controller.query.trim().isNotEmpty;
    final status = !hasQuery
        ? null
        : total == 0
            ? l10n.findNone
            : l10n.findCount(controller.current + 1, total);
    void selectAll() => text.selection =
        TextSelection(baseOffset: 0, extentOffset: text.text.length);
    // The whole bar counts as the field: its buttons keep typing focus.
    return TextFieldTapRegion(
      child: HwGlass(
        strong: true,
        borderRadius: BorderRadius.circular(HwTheme.rLg),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              HwIcon('search', size: 16, color: p.ink3),
              const SizedBox(width: 8),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): onNext,
                    const SingleActivator(LogicalKeyboardKey.numpadEnter):
                        onNext,
                    const SingleActivator(LogicalKeyboardKey.enter,
                        shift: true): onPrevious,
                    const SingleActivator(LogicalKeyboardKey.escape): onClose,
                    const SingleActivator(LogicalKeyboardKey.keyF,
                        control: true): selectAll,
                    const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                        selectAll,
                  },
                  child: TextField(
                    controller: text,
                    focusNode: focus,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    onTapOutside: (_) => onTapOutside(),
                    onSubmitted: (_) {
                      onNext();
                      focus.requestFocus();
                    },
                    style: TextStyle(fontSize: 14, color: p.ink0),
                    cursorColor: p.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: l10n.findHint,
                      hintStyle: TextStyle(color: p.ink3),
                    ),
                  ),
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: total == 0 ? p.ink3 : p.ink2,
                    fontFamily: HwTheme.fontMono,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const HwDivider(),
              HwButton.icon(
                icon: const HwIcon('chevron-up', size: 16),
                tooltip: l10n.findPrevious,
                onPressed: total > 0 ? onPrevious : null,
              ),
              HwButton.icon(
                icon: const HwIcon('chevron-down', size: 16),
                tooltip: l10n.findNext,
                onPressed: total > 0 ? onNext : null,
              ),
              HwButton.icon(
                icon: const HwIcon('x', size: 14),
                tooltip: l10n.findClose,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches on the visible page as marker swipes; the current one also gets
/// an ink underline.
class FindHighlightPainter extends CustomPainter {
  final List<Rect> others;
  final List<Rect> current;
  final Color marker;
  final Color ink;

  FindHighlightPainter({
    required this.others,
    required this.current,
    required this.marker,
    required this.ink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = marker.withValues(alpha: 0.18);
    final strong = Paint()..color = marker.withValues(alpha: 0.4);
    for (final r in others) {
      canvas.drawRRect(_swipe(r), soft);
    }
    if (current.isEmpty) return;
    final line = Paint()
      ..color = ink
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final r in current) {
      canvas.drawRRect(_swipe(r), strong);
      final y = r.bottom + 2;
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), line);
    }
  }

  RRect _swipe(Rect r) {
    final pad = (r.height * 0.12).clamp(1.0, 6.0);
    return RRect.fromRectAndRadius(
        r.inflate(pad), Radius.circular((r.height * 0.25).clamp(2.0, 8.0)));
  }

  @override
  bool shouldRepaint(FindHighlightPainter old) =>
      old.marker != marker ||
      old.ink != ink ||
      !_same(old.others, others) ||
      !_same(old.current, current);

  static bool _same(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
