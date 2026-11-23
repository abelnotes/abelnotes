// The circuit detector's CPU engine (packages/circuit_engine): dart:ffi on
// native platforms, its WebAssembly build on the web; the stub (the detector
// in Dart) anywhere else.
export 'native_engine_stub.dart'
    if (dart.library.ffi) 'native_engine_ffi.dart'
    if (dart.library.js_interop) 'native_engine_web.dart';
