import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the user picked on a read-only preview of a notebook file.
enum PreviewChoice { addToLibrary, openLibraryCopy }

/// A notebook file opened from outside the app (double-click, command line),
/// shown read-only until the user adds it.
class NotebookPreview {
  /// The file's name, as the user knows it.
  final String fileName;

  /// The library notebook this file was exported from, if any.
  final String? libraryCopyId;

  const NotebookPreview({required this.fileName, this.libraryCopyId});
}

/// Set while the editor shows a [NotebookPreview].
final notebookPreviewProvider =
    StateProvider<NotebookPreview?>((ref) => null);
