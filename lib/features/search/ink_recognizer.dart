// Handwriting line recognizer on the native engine (abnn in
// packages/circuit_engine); none on the web yet.
export 'ink_recognizer_stub.dart' if (dart.library.ffi) 'ink_recognizer_ffi.dart';
