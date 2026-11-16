import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_screen.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Notebook shown read-only beside the editor, by id. Reset when the editor
/// route goes away (nothing watches it any more).
final referenceNotebookProvider =
    StateProvider.autoDispose<String?>((ref) => null);

/// Share of the editor area the side notebook takes, kept while the app runs.
final _referenceFractionProvider = StateProvider<double>((ref) => 0.4);

class _NotAvailable implements Exception {
  @override
  String toString() => 'notebook not on this device and app offline';
}

/// Read-only copy of a notebook: from its folder on disk, the legacy file,
/// or straight from the server for one this device doesn't hold. Never
/// written back, never added to the library.
final _referenceContentsProvider = FutureProvider.autoDispose
    .family<LooseStoreContents, String>((ref, id) async {
  final files = ref.read(fileServiceProvider);
  final sync = ref.read(syncServiceProvider);
  if (sync == null) throw _NotAvailable();
  if (await files.hasLooseStore(id)) {
    final c = await sync.loadLooseStoreFromDisk(files.notebookStoreDir(id));
    if (c != null) return c;
  }
  final bytes = await files.readNotebookFile(id);
  if (bytes != null) return sync.parsePackage(bytes);
  if (sync.isOffline) throw _NotAvailable();
  return sync.downloadExplodedFull(id);
});

/// The editor, plus the side notebook when one is open: beside it on wide
/// screens, below it on narrow ones. The editor always starts at the
/// top-left corner, so its pointer and overlay coordinates don't change.
class EditorWithReference extends ConsumerStatefulWidget {
  const EditorWithReference({super.key});

  @override
  ConsumerState<EditorWithReference> createState() =>
      _EditorWithReferenceState();
}

class _EditorWithReferenceState extends ConsumerState<EditorWithReference> {
  // Keeps the editor's state when the layout around it changes: rebuilding
  // it would close the notebook.
  final _editorKey = GlobalKey();

  static const _divider = 8.0;

  @override
  Widget build(BuildContext context) {
    final refId = ref.watch(referenceNotebookProvider);
    final editor = KeyedSubtree(key: _editorKey, child: const CanvasScreen());
    if (refId == null) return editor;
    final p = HwThemeScope.of(context);
    final fraction = ref.watch(_referenceFractionProvider);
    return LayoutBuilder(builder: (context, c) {
      final mq = MediaQuery.of(context);
      final wide = c.maxWidth >= 720 && c.maxWidth >= c.maxHeight * 0.9;
      final total = wide ? c.maxWidth : c.maxHeight;
      final minEditor = wide ? 360.0 : 280.0;
      final paneSize = (total * fraction)
          .clamp(math.min(220.0, total / 3), math.max(220.0, total - minEditor))
          .toDouble();
      final editorSize = total - paneSize - _divider;
      final editorBox = MediaQuery(
        data: mq.copyWith(
          size: wide
              ? Size(editorSize, mq.size.height)
              : Size(mq.size.width, editorSize),
        ),
        child: editor,
      );
      final handle = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: wide
            ? (d) => _resize(-d.delta.dx / total, total)
            : null,
        onVerticalDragUpdate: wide
            ? null
            : (d) => _resize(-d.delta.dy / total, total),
        child: MouseRegion(
          cursor: wide
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: Container(
            color: p.paper2,
            alignment: Alignment.center,
            child: Container(
              width: wide ? 3 : 36,
              height: wide ? 36 : 3,
              decoration: BoxDecoration(
                color: p.ink3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
      final pane = SafeArea(
        left: !wide,
        top: !wide,
        child: ReferencePane(notebookId: refId),
      );
      return Material(
        color: p.paper1,
        child: Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: wide ? editorSize : null,
              height: wide ? null : editorSize,
              child: editorBox,
            ),
            SizedBox(
              width: wide ? _divider : null,
              height: wide ? null : _divider,
              child: handle,
            ),
            Expanded(child: pane),
          ],
        ),
      );
    });
  }

  void _resize(double delta, double total) {
    final n = ref.read(_referenceFractionProvider.notifier);
    n.state = (n.state + delta).clamp(0.2, 0.7);
  }
}

/// Pages of a notebook, read-only, fitted to the pane width.
class ReferencePane extends ConsumerStatefulWidget {
  final String notebookId;
  const ReferencePane({super.key, required this.notebookId});

  @override
  ConsumerState<ReferencePane> createState() => _ReferencePaneState();
}

class _ReferencePaneState extends ConsumerState<ReferencePane> {
  final _scroll = ScrollController();
  final _hscroll = ScrollController();
  final _viewportKey = GlobalKey();
  double? _pendingY, _pendingX;
  final _images = _ImageCache();
  final _current = ValueNotifier<int>(0);
  double _zoom = 1;
  final Map<int, Offset> _pointers = {};
  double? _pinchStart;
  double _pinchZoom = 1;
  List<double> _pageTops = const [];

  static const _gap = 12.0;
  static const _pad = 12.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackPage);
  }

  @override
  void didUpdateWidget(ReferencePane old) {
    super.didUpdateWidget(old);
    if (old.notebookId != widget.notebookId) {
      _images.clear();
      _current.value = 0;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _hscroll.dispose();
    _images.clear();
    _current.dispose();
    super.dispose();
  }

  void _trackPage() {
    final y = _scroll.offset + 1;
    var i = 0;
    while (i + 1 < _pageTops.length && _pageTops[i + 1] <= y) {
      i++;
    }
    _current.value = i;
  }

  /// Zooms around [focal] (global position; default the pane centre), so
  /// what is under the fingers stays there.
  void _setZoom(double z, {Offset? focal}) {
    final next = z.clamp(1.0, 4.0);
    if (next == _zoom) return;
    final ratio = next / _zoom;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final local = box == null
        ? Offset.zero
        : (focal == null
            ? box.size.center(Offset.zero)
            : box.globalToLocal(focal));
    // Several pointer moves land between two frames: build on the offset
    // still waiting to be applied, not the stale one.
    final y = _pendingY ?? (_scroll.hasClients ? _scroll.offset : 0.0);
    final x = _pendingX ?? (_hscroll.hasClients ? _hscroll.offset : 0.0);
    final firstInFrame = _pendingY == null;
    _pendingY = (y + local.dy) * ratio - local.dy;
    _pendingX = (x + local.dx) * ratio - local.dx;
    setState(() => _zoom = next);
    if (!firstInFrame) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ty = _pendingY ?? 0, tx = _pendingX ?? 0;
      _pendingY = _pendingX = null;
      if (_scroll.hasClients) {
        _scroll.jumpTo(ty.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
      }
      if (_hscroll.hasClients) {
        _hscroll.jumpTo(tx.clamp(0.0, _hscroll.position.maxScrollExtent).toDouble());
      }
    });
  }

  // Two fingers anywhere on the pane zoom it; one scrolls as usual.
  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStart = _spread();
      _pinchZoom = _zoom;
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _pinchStart;
    if (_pointers.length == 2 && start != null && start > 0) {
      final pts = _pointers.values.toList();
      _setZoom(_pinchZoom * _spread() / start,
          focal: (pts[0] + pts[1]) / 2);
    }
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStart = null;
  }

  double _spread() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final contents =
        ref.watch(_referenceContentsProvider(widget.notebookId));
    final title = contents.valueOrNull?.metadata.title ??
        _titleFromLibrary(ref, widget.notebookId);
    final pages = contents.valueOrNull == null
        ? const <PageData>[]
        : _orderedPages(contents.value!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.paper3)),
          ),
          child: Row(children: [
            HwIcon('book', size: 16, color: p.ink2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HwType.callout
                      .copyWith(color: p.ink0, fontWeight: FontWeight.w600)),
            ),
            if (pages.isNotEmpty)
              ValueListenableBuilder<int>(
                valueListenable: _current,
                builder: (_, i, __) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('${i + 1} / ${pages.length}',
                      style: HwType.footnote.copyWith(color: p.ink2)),
                ),
              ),
            _HeaderButton(
              icon: 'minus',
              tooltip: l10n.refZoomOut,
              onTap: _zoom > 1 ? () => _setZoom(_zoom / 1.25) : null,
            ),
            _HeaderButton(
              icon: 'plus',
              tooltip: l10n.refZoomIn,
              onTap: _zoom < 4 ? () => _setZoom(_zoom * 1.25) : null,
            ),
            _HeaderButton(
              icon: 'x',
              tooltip: l10n.csClose,
              onTap: () =>
                  ref.read(referenceNotebookProvider.notifier).state = null,
            ),
          ]),
        ),
        Expanded(
          child: contents.when(
            loading: () => const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.refLoadFailed,
                    textAlign: TextAlign.center,
                    style: HwType.callout.copyWith(color: p.ink2)),
              ),
            ),
            data: (c) => _pagesView(c, pages, p),
          ),
        ),
      ],
    );
  }

  Widget _pagesView(LooseStoreContents c, List<PageData> pages, HwPalette p) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth * _zoom;
      final pageWidth = math.max(1.0, width - 2 * _pad);
      final tops = <double>[];
      var y = _pad;
      for (final page in pages) {
        tops.add(y);
        y += pageWidth * page.height / page.width + _gap;
      }
      _pageTops = tops;
      final list = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(_pad),
        itemCount: pages.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: _ReferencePage(
            page: pages[i],
            assets: c.assets,
            images: _images,
            paperEdge: p.paper3,
          ),
        ),
      );
      final body = _zoom == 1
          ? list
          : SingleChildScrollView(
              controller: _hscroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: width, child: list),
            );
      return Listener(
        key: _viewportKey,
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: body,
      );
    });
  }

  static List<PageData> _orderedPages(LooseStoreContents c) => [
        for (final e in c.document.pages)
          if (c.pages[e.fileName] != null) c.pages[e.fileName]!,
      ];

  static String _titleFromLibrary(WidgetRef ref, String id) {
    final list = ref.read(notebookListProvider).valueOrNull ?? const [];
    for (final e in list) {
      if (e.metadata.id == id) return e.metadata.title;
    }
    return '';
  }
}

class _HeaderButton extends StatelessWidget {
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _HeaderButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: HwIcon(icon, size: 18, color: onTap == null ? p.ink3 : p.ink1),
    );
  }
}

/// One page, painted by the editor's engine, with its pictures decoded on
/// first show.
class _ReferencePage extends StatefulWidget {
  final PageData page;
  final Map<String, Uint8List> assets;
  final _ImageCache images;
  final Color paperEdge;
  const _ReferencePage({
    required this.page,
    required this.assets,
    required this.images,
    required this.paperEdge,
  });

  @override
  State<_ReferencePage> createState() => _ReferencePageState();
}

class _ReferencePageState extends State<_ReferencePage> {
  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_ReferencePage old) {
    super.didUpdateWidget(old);
    if (!identical(old.page, widget.page)) _decode();
  }

  void _decode() {
    final refs = <String>{};
    for (final el in widget.page.layers.content) {
      el.mapOrNull(image: (img) {
        if (img.data.assetPath.isNotEmpty) refs.add(img.data.assetPath);
      });
    }
    if (refs.isEmpty) return;
    widget.images.ensure(refs, widget.assets).then((changed) {
      if (changed && mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return AspectRatio(
      aspectRatio: page.width / page.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(page.layers.background.color),
          border: Border.all(color: widget.paperEdge),
        ),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: CanvasRenderEngine(
              pageData: page,
              // A copy: the painter repaints only when the image set differs
              // from its previous one, which the same mutated map never does.
              imageCache: Map.of(widget.images.map),
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Decoded pictures of the side notebook, newest kept: a PDF of hundreds of
/// page images would otherwise stay in memory as the user scrolls.
class _ImageCache {
  static const _cap = 24;
  final Map<String, ui.Image> map = {};
  final Map<String, Future<void>> _pending = {};
  final List<String> _order = [];

  /// Decodes what is missing; true when anything new became available.
  Future<bool> ensure(Set<String> refs, Map<String, Uint8List> assets) async {
    var changed = false;
    for (final r in refs) {
      _order
        ..remove(r)
        ..add(r);
      if (map.containsKey(r)) continue;
      final bytes = assets[r];
      if (bytes == null) continue;
      final job = _pending[r] ??= () async {
        try {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          map[r] = frame.image;
        } catch (_) {/* shown as a missing picture */}
      }();
      await job;
      _pending.remove(r);
      changed = true;
    }
    while (_order.length > _cap) {
      final old = _order.removeAt(0);
      if (refs.contains(old)) break;
      map.remove(old)?.dispose();
    }
    return changed;
  }

  void clear() {
    for (final img in map.values) {
      img.dispose();
    }
    map.clear();
    _order.clear();
  }
}

/// Lists the other notebooks; picking one opens it beside the editor.
Future<void> showReferencePicker(
    BuildContext context, WidgetRef ref, String currentId) {
  final l10n = AppLocalizations.of(context);
  final p = HwThemeScope.of(context);
  final entries = [
    for (final e in ref.read(notebookListProvider).valueOrNull ?? const [])
      if (e.metadata.id != currentId) e,
  ]..sort((a, b) => b.metadata.modifiedAt.compareTo(a.metadata.modifiedAt));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.paper0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(l10n.refPickTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(l10n.refNoOthers,
                    style: HwType.callout.copyWith(color: p.ink2)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      leading: Container(
                        width: 22,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(e.metadata.coverColor),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      title: Text(e.metadata.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: e.notOnDevice
                          ? HwIcon('cloud-download', size: 18, color: p.ink2)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        ref.read(referenceNotebookProvider.notifier).state =
                            e.metadata.id;
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
