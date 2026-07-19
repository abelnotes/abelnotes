import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// A single file that was shared into HandWriter from another app. The
/// library screen listens for these and prompts the user to decide where
/// to import it (existing notebook / chapter / new notebook).
@immutable
class SharedImport {
  final List<SharedMediaFile> files;

  const SharedImport(this.files);

  /// Whether every file is application/pdf.
  bool get allPdf {
    for (final f in files) {
      final path = f.path.toLowerCase();
      final isPdf = path.endsWith('.pdf') ||
          (f.mimeType?.toLowerCase() == 'application/pdf');
      if (!isPdf) return false;
    }
    return files.isNotEmpty;
  }
}

/// Emits a [SharedImport] every time the OS hands us one or more files
/// via the Android SEND / iOS share sheet.
///
/// Safe to read on desktop platforms — the plugin simply never fires
/// there.
final shareReceiverProvider =
    StateNotifierProvider<ShareReceiver, SharedImport?>((ref) {
  final notifier = ShareReceiver();
  notifier._start();
  ref.onDispose(notifier.dispose);
  return notifier;
});

class ShareReceiver extends StateNotifier<SharedImport?> {
  ShareReceiver() : super(null);

  StreamSubscription<List<SharedMediaFile>>? _sub;

  /// The plugin only supports Android + iOS. On every other platform the
  /// listener is a no-op so the provider can still be read safely.
  bool get _isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _start() async {
    if (!_isSupported) return;
    try {
      // Pick up a share that launched the app cold.
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        state = SharedImport(initial);
        // Tell the plugin we consumed the initial media so the next app
        // launch doesn't replay it.
        ReceiveSharingIntent.instance.reset();
      }
      // Listen for subsequent shares while the app is running.
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        if (files.isEmpty) return;
        state = SharedImport(files);
      }, onError: (e) {
        debugPrint('[ShareReceiver] stream error: $e');
      });
    } catch (e) {
      debugPrint('[ShareReceiver] init failed: $e');
    }
  }

  /// Called by the UI after it has handled (or dismissed) a pending share
  /// so we don't re-open the destination picker on the next rebuild.
  void consume() {
    state = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
