// Region router (text / formula / circuit / drawing) on the native engine
// (abnn in packages/circuit_engine), as WebAssembly in a worker on the web.
export 'region_route.dart';
export 'region_router_stub.dart'
    if (dart.library.ffi) 'region_router_ffi.dart'
    if (dart.library.js_interop) 'region_router_web.dart';
