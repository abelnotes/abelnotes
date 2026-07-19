import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Full-featured symbol library side panel.
/// Shows libraries in a left column, symbols in a grid on the right.
/// Supports: multiple libraries, previews, insert on tap, rename/delete.
class SymbolLibraryPanel extends ConsumerStatefulWidget {
  final Offset insertPos;
  final VoidCallback onClose;

  const SymbolLibraryPanel({
    super.key,
    required this.insertPos,
    required this.onClose,
  });

  @override
  ConsumerState<SymbolLibraryPanel> createState() => _SymbolLibraryPanelState();
}

class _SymbolLibraryPanelState extends ConsumerState<SymbolLibraryPanel> {
  String? _selectedLibId;
  final _previewCache = <String, ui.Image>{};

  @override
  void initState() {
    super.initState();
    // Select first library by default
    final libs = ref.read(canvasProvider)?.symbolLibraries ?? [];
    _selectedLibId = libs.isNotEmpty ? libs.first.id : null;
  }

  @override
  void dispose() {
    for (final img in _previewCache.values) {
      img.dispose();
    }
    super.dispose();
  }

  void _ensurePreviewsFor(SymbolLibrary lib, Map<String, ui.Image> imageCache) {
    for (final sym in lib.symbols) {
      if (!_previewCache.containsKey(sym.id)) {
        _renderSymbolPreview(sym, imageCache);
      }
    }
  }

  Future<void> _renderSymbolPreview(ReusableSymbol symbol, Map<String, ui.Image> imageCache) async {
    const previewSize = 64.0;
    if (symbol.bounds.width <= 0 || symbol.bounds.height <= 0) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Fill white background
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, previewSize, previewSize),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final scaleX = (previewSize - 8) / symbol.bounds.width;
    final scaleY = (previewSize - 8) / symbol.bounds.height;
    final scale = min(scaleX, scaleY);
    final dx = 4.0 - symbol.bounds.left * scale + (previewSize - 8 - symbol.bounds.width * scale) / 2;
    final dy = 4.0 - symbol.bounds.top * scale + (previewSize - 8 - symbol.bounds.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    for (final element in symbol.elements) {
      element.map(
        stroke: (e) {
          if (e.data.points.length < 2) return;
          final paint = Paint()
            ..color = Color(e.data.color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (e.data.baseWidth * 0.6).clamp(0.5, 4.0)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          final path = Path()
            ..moveTo(e.data.points.first.x, e.data.points.first.y);
          for (int i = 1; i < e.data.points.length; i++) {
            path.lineTo(e.data.points[i].x, e.data.points[i].y);
          }
          canvas.drawPath(path, paint);
        },
        shape: (e) {
          final d = e.data;
          final paint = Paint()
            ..color = Color(d.strokeColor)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (d.strokeWidth * 0.6).clamp(0.5, 3.0)
            ..isAntiAlias = true;
          switch (d.shapeType) {
            case 'rectangle':
              canvas.drawRect(Rect.fromLTRB(d.x1, d.y1, d.x2, d.y2), paint);
              break;
            case 'circle':
              final cx = (d.x1 + d.x2) / 2;
              final cy = (d.y1 + d.y2) / 2;
              final r = Offset(d.x2 - d.x1, d.y2 - d.y1).distance / 2;
              canvas.drawCircle(Offset(cx, cy), r, paint);
              break;
            case 'line':
            case 'arrow':
              canvas.drawLine(Offset(d.x1, d.y1), Offset(d.x2, d.y2), paint);
              break;
            case 'triangle':
              final path = Path()
                ..moveTo((d.x1 + d.x2) / 2, d.y1)
                ..lineTo(d.x1, d.y2)
                ..lineTo(d.x2, d.y2)
                ..close();
              canvas.drawPath(path, paint);
              break;
          }
        },
        text: (e) {
          final tp = TextPainter(
            text: TextSpan(
              text: e.data.content,
              style: TextStyle(fontSize: 8, color: Color(e.data.color)),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(e.data.x, e.data.y));
        },
        image: (_) {},
        math: (_) {},
      );
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(previewSize.toInt(), previewSize.toInt());
    if (mounted) {
      setState(() => _previewCache[symbol.id] = img);
    }
  }

  Future<void> _createLibrary() async {
    final l10n = AppLocalizations.of(context);
    final name = await _promptName(
        context, l10n.symNewLibraryTitle, l10n.symNewLibraryHint);
    if (name == null || name.trim().isEmpty) return;
    ref.read(canvasProvider.notifier).createSymbolLibrary(name.trim());
    final libs = ref.read(canvasProvider)?.symbolLibraries ?? [];
    if (libs.isNotEmpty && mounted) setState(() => _selectedLibId = libs.last.id);
  }

  Future<void> _renameLibrary(SymbolLibrary lib) async {
    final l10n = AppLocalizations.of(context);
    final name = await _promptName(
        context, l10n.symRenameLibraryTitle, l10n.symNewNameHint,
        initial: lib.name);
    if (name == null || name.trim().isEmpty) return;
    ref.read(canvasProvider.notifier).renameSymbolLibrary(lib.id, name.trim());
  }

  Future<void> _deleteLibrary(SymbolLibrary lib) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.symDeleteLibraryTitle),
        content: Text(l10n.symDeleteLibraryConfirm(lib.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.symCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.symDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(canvasProvider.notifier).deleteSymbolLibrary(lib.id);
    if (mounted) setState(() => _selectedLibId = null);
  }

  void _deleteSymbol(String libId, String symId) {
    ref.read(canvasProvider.notifier).deleteSymbolFromLibrary(libId, symId);
    setState(() => _previewCache.remove(symId));
  }

  Future<void> _renameSymbol(String libId, ReusableSymbol sym) async {
    final l10n = AppLocalizations.of(context);
    final name = await _promptName(
        context, l10n.symRenameSymbolTitle, l10n.symNewNameHint,
        initial: sym.name);
    if (name == null || name.trim().isEmpty) return;
    ref.read(canvasProvider.notifier).renameSymbol(libId, sym.id, name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(canvasProvider);
    if (state == null) return const SizedBox.shrink();

    final libs = state.symbolLibraries;
    final selLib = libs.where((l) => l.id == _selectedLibId).firstOrNull;
    if (selLib != null) _ensurePreviewsFor(selLib, state.imageCache);

    final p = HwThemeScope.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainer = Theme.of(context).colorScheme.surfaceContainer;
    final surfaceContainerHighest = Theme.of(context).colorScheme.surfaceContainerHighest;
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    final textStrong = Theme.of(context).colorScheme.onSurface;
    final textMuted = Theme.of(context).colorScheme.onSurfaceVariant;

    final screen = MediaQuery.sizeOf(context);
    final maxWidth = min(560.0, screen.width - 48);
    final maxHeight = min(440.0, screen.height - 100);
    final sidebarWidth = (screen.width * 0.25).clamp(110.0, 150.0);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Container(
        decoration: BoxDecoration(
          color: isDark ? surfaceContainer : p.paper0,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // ── Title bar ──
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? surfaceContainerHighest : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(Icons.library_books_rounded, size: 18, color: p.accent),
                  const SizedBox(width: 8),
                  Text(l10n.symPanelTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            // ── Body: libs list + symbols grid ──
            Expanded(
              child: Row(
                children: [
                  // Library list
                  SizedBox(
                    width: sidebarWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? surfaceContainerHighest : Colors.white,
                        border: Border(right: BorderSide(color: outlineVariant)),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: libs.isEmpty
                                ? Center(
                                    child: Text(l10n.symNoLibraries,
                                        style: TextStyle(fontSize: 11, color: textMuted),
                                        textAlign: TextAlign.center),
                                  )
                                : ListView.builder(
                                    itemCount: libs.length,
                                    itemBuilder: (ctx, i) {
                                      final lib = libs[i];
                                      final sel = lib.id == _selectedLibId;
                                      return GestureDetector(
                                        onTap: () => setState(() => _selectedLibId = lib.id),
                                        onSecondaryTapDown: (_) => _showLibContextMenu(context, lib),
                                        child: Container(
                                          color: sel ? p.accentSoft : Colors.transparent,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          child: Row(
                                            children: [
                                              Icon(Icons.folder_rounded, size: 15,
                                                  color: sel ? p.accent : textMuted),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(lib.name,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                                                      color: sel ? p.accentDeep : textStrong,
                                                    ),
                                                    overflow: TextOverflow.ellipsis),
                                              ),
                                              Text('${lib.symbols.length}',
                                                  style: TextStyle(fontSize: 10, color: textMuted)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.add, size: 14),
                                label: Text(l10n.symNew, style: const TextStyle(fontSize: 12)),
                                onPressed: _createLibrary,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Symbols grid
                  Expanded(
                    child: selLib == null
                        ? Center(
                            child: Text(l10n.symSelectLibrary,
                                style: TextStyle(color: textMuted, fontSize: 13)),
                          )
                        : selLib.symbols.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_border_rounded, size: 40, color: textMuted),
                                    const SizedBox(height: 8),
                                    Text(l10n.symNoSymbolsHint,
                                        style: TextStyle(color: textMuted, fontSize: 12),
                                        textAlign: TextAlign.center),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 90,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 0.75,
                                ),
                                itemCount: selLib.symbols.length,
                                itemBuilder: (ctx, i) {
                                  final sym = selLib.symbols[i];
                                  return _SymbolTile(
                                    symbol: sym,
                                    preview: _previewCache[sym.id],
                                    onInsert: () {
                                      ref.read(canvasProvider.notifier).setPendingSymbol(sym);
                                      widget.onClose();
                                    },
                                    onDelete: () => _deleteSymbol(selLib.id, sym.id),
                                    onRename: () => _renameSymbol(selLib.id, sym),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            // ── Bottom bar: add symbol from selection hint ──
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? surfaceContainerHighest : Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border(top: BorderSide(color: outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: textMuted),
                  const SizedBox(width: 6),
                  Text(
                    l10n.symLassoSaveHint,
                    style: TextStyle(fontSize: 11, color: textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showLibContextMenu(BuildContext context, SymbolLibrary lib) {
    final l10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromSize(
        const Rect.fromLTWH(150, 100, 0, 0), overlay.size),
      items: [
        PopupMenuItem(
          onTap: () => _renameLibrary(lib),
          child: Row(children: [
            const Icon(Icons.edit, size: 16),
            const SizedBox(width: 8),
            Text(l10n.symRename),
          ]),
        ),
        PopupMenuItem(
          onTap: () => _deleteLibrary(lib),
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
            const SizedBox(width: 8),
            Text(l10n.symDelete, style: TextStyle(color: Colors.red.shade400)),
          ]),
        ),
      ],
    );
  }
}

class _SymbolTile extends StatelessWidget {
  final ReusableSymbol symbol;
  final ui.Image? preview;
  final VoidCallback onInsert;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _SymbolTile({
    required this.symbol,
    required this.preview,
    required this.onInsert,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final textStrong = Theme.of(context).colorScheme.onSurface;
    final shadowColor = Theme.of(context).colorScheme.shadow;
    return GestureDetector(
      onTap: onInsert,
      onSecondaryTapDown: (_) => _showContextMenu(context),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                // Preview images are rasterized on white, so keep white here
                // to match the baked background (avoids a grey halo in dark mode).
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: outline),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: preview != null
                    ? RawImage(image: preview, fit: BoxFit.contain)
                    : const Center(child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 1.5))),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            symbol.name,
            style: TextStyle(fontSize: 10, color: textStrong),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(200, 200, 0, 0),
      items: [
        PopupMenuItem(
          onTap: onInsert,
          child: Row(children: [
            const Icon(Icons.add_circle_outline, size: 16),
            const SizedBox(width: 8),
            Text(l10n.symInsert),
          ]),
        ),
        PopupMenuItem(
          onTap: onRename,
          child: Row(children: [
            const Icon(Icons.edit, size: 16),
            const SizedBox(width: 8),
            Text(l10n.symRename),
          ]),
        ),
        PopupMenuItem(
          onTap: onDelete,
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
            const SizedBox(width: 8),
            Text(l10n.symDelete, style: TextStyle(color: Colors.red.shade400)),
          ]),
        ),
      ],
    );
  }
}

Future<String?> _promptName(BuildContext context, String title, String hint, {String initial = ''}) async {
  final l10n = AppLocalizations.of(context);
  final ctrl = TextEditingController(text: initial);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.symCancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(l10n.symOk),
          ),
        ],
      ),
    );
  } finally {
    ctrl.dispose();
  }
}
