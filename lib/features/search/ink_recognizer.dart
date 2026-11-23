// Handwriting line recognizer on the native engine (abnn in
// packages/circuit_engine), as WebAssembly in a worker on the web.
export 'ink_recognizer_stub.dart'
    if (dart.library.ffi) 'ink_recognizer_ffi.dart'
    if (dart.library.js_interop) 'ink_recognizer_web.dart';
