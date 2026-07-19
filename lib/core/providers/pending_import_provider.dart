import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Files that the user asked to import into the *next* notebook they open.
///
/// Set by the library when a share arrives and the user picks a destination.
/// The canvas screen consumes this on open, runs the usual image/PDF insert
/// flow, then clears the provider.
class PendingImport {
  /// Absolute paths on disk. Each file is imported in order.
  final List<String> filePaths;

  /// Optional chapter id to drop the imported pages into. When null, the
  /// canvas uses the currently-active chapter (or the first one).
  final String? targetChapterId;

  /// When true, a brand new chapter with this title is created before
  /// importing the pages. Ignored if [targetChapterId] is set.
  final String? newChapterTitle;

  const PendingImport({
    required this.filePaths,
    this.targetChapterId,
    this.newChapterTitle,
  });
}

final pendingImportProvider = StateProvider<PendingImport?>((_) => null);
