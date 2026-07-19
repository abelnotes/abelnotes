import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';

/// Clipboard that survives notebook close/open so the user can copy
/// elements from one notebook and paste them into another.
/// Cleared automatically once it has been consumed (pasted).
final crossNotebookClipboardProvider =
    StateProvider<CanvasClipboard?>((_) => null);
