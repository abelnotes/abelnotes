import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/config/app_config.dart';

/// A notebook the OS asked us to open — a `.ncnote` double-click, or a path on
/// the command line.
@immutable
class PendingFileOpen {
  final String path;

  const PendingFileOpen(this.path);
}

/// Warm opens (app already running) come from the Windows runner over this
/// channel; see windows/runner/app_ipc.h. Cold opens arrive as argv instead.
const MethodChannel _channel = MethodChannel('abelnotes/file_open');

/// Emits a [PendingFileOpen] when the OS hands us a notebook to open. The
/// library screen listens and runs it through the normal import pipeline.
///
/// [FileOpenReceiver.initialArgs] carries the cold-start path, so main.dart
/// overrides this provider with the real `main(args)`. Reading it unoverridden
/// is safe — it just never fires.
final fileOpenReceiverProvider =
    StateNotifierProvider<FileOpenReceiver, PendingFileOpen?>((ref) {
  final notifier = FileOpenReceiver();
  notifier.start();
  return notifier;
});

class FileOpenReceiver extends StateNotifier<PendingFileOpen?> {
  FileOpenReceiver({List<String> initialArgs = const []})
      : _initialArgs = initialArgs,
        super(null);

  final List<String> _initialArgs;

  /// Only the Windows runner implements the warm-open channel. Cold-start
  /// argv works on every desktop platform, since all three runners forward
  /// the command line to the Dart entrypoint.
  bool get _hasWarmChannel => !kIsWeb && Platform.isWindows;

  void start() {
    final initial = notebookPathFrom(_initialArgs);
    if (initial != null) {
      state = PendingFileOpen(initial);
    }
    if (_hasWarmChannel) {
      _channel.setMethodCallHandler(_onCall);
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'open') return;
    final argument = call.arguments;
    if (argument is! String) return;
    final resolved = notebookPathFrom([argument]);
    if (resolved != null) {
      state = PendingFileOpen(resolved);
    }
  }

  /// First argument naming an existing notebook file, in either the current or
  /// the pre-rename spelling. The Windows runner already drops non-files, but
  /// `flutter run` adds flags of its own and the other runners don't filter.
  static String? notebookPathFrom(List<String> args) {
    for (final arg in args) {
      if (!AppConfig.isNotebookPath(arg)) continue;
      if (!File(arg).existsSync()) continue;
      return arg;
    }
    return null;
  }

  /// Called by the UI once it has handled (or dismissed) the request, so the
  /// import doesn't re-trigger on the next rebuild.
  void consume() {
    state = null;
  }

  @override
  void dispose() {
    if (_hasWarmChannel) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
