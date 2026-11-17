import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:abelnotes/core/platform/io.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Files dragged in from the file manager on desktop: [onDrop] gets their
/// local paths and the drop point in this widget's coordinates. Elsewhere it
/// is just [child].
class FileDropZone extends StatefulWidget {
  final Widget child;

  /// Shown over [child] while files hover it.
  final String hint;
  final void Function(List<String> paths, Offset local) onDrop;

  const FileDropZone({
    super.key,
    required this.child,
    required this.hint,
    required this.onDrop,
  });

  static bool get supported =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _over = false;

  void _setOver(bool v) {
    if (mounted && v != _over) setState(() => _over = v);
  }

  static bool _hasFiles(DropSession s) =>
      s.items.any((i) => i.canProvide(Formats.fileUri));

  Future<void> _perform(PerformDropEvent e) async {
    final paths = <String>[];
    for (final item in e.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;
      final done = Completer<Uri?>();
      final progress = reader.getValue<Uri>(
        Formats.fileUri,
        (uri) => done.complete(uri),
        onError: (_) => done.complete(null),
      );
      if (progress == null) continue; // not a file: the callback never runs
      final uri = await done.future;
      final path = uri == null ? null : dropUriPath(uri);
      if (path != null) paths.add(path);
    }
    if (paths.isNotEmpty) widget.onDrop(paths, e.position.local);
  }

  @override
  Widget build(BuildContext context) {
    if (!FileDropZone.supported) return widget.child;
    final p = HwThemeScope.of(context);
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.translucent,
      onDropOver: (e) =>
          _hasFiles(e.session) &&
                  e.session.allowedOperations.contains(DropOperation.copy)
              ? DropOperation.copy
              : DropOperation.none,
      onDropEnter: (e) => _setOver(_hasFiles(e.session)),
      onDropLeave: (_) => _setOver(false),
      onDropEnded: (_) => _setOver(false),
      onPerformDrop: (e) async {
        _setOver(false);
        await _perform(e);
      },
      // The child stays the Stack's first entry so its state survives the
      // overlay coming and going.
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.08),
                    border: Border.all(color: p.accent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(widget.hint,
                        style: HwType.callout.copyWith(
                            color: p.onAccent, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Local path of a dropped file URI, or null when it is not a usable file.
/// Some senders put a host in it (file://host/path), which toFilePath()
/// rejects on Linux and macOS: the host is dropped and the path kept.
@visibleForTesting
String? dropUriPath(Uri uri) {
  if (!uri.isScheme('file')) return null;
  try {
    return (uri.host.isEmpty ? uri : uri.replace(host: '')).toFilePath();
  } catch (_) {
    return null;
  }
}
