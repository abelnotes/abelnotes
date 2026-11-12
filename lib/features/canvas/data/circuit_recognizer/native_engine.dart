// The circuit detector's native CPU engine (packages/circuit_engine), where
// dart:ffi exists; elsewhere (web) the detector runs in Dart.
export 'native_engine_stub.dart' if (dart.library.ffi) 'native_engine_ffi.dart';
