import 'package:abelnotes/core/platform/io_web.dart';

/// IndexedDB per origin: contribute.abelnotes.app keeps its own queue, apart
/// from the notes of app.abelnotes.app.
Future<void> initPageStorage() => WebFs.init();
