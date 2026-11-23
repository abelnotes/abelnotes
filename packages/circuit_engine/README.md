# circuit_engine

The recognizers' CPU engine in C (`src/`): the circuit detector's forward pass
(`circuit_engine.c`), the picture passes (`image_ink.c`), and `abnn` (`abnn.c`,
`region_router.c`) for the handwriting OCR and region router models, bound from
the app with dart:ffi. An FFI plugin so each platform's Flutter build compiles it
from source (CMake on Linux, Windows and Android, CocoaPods forwarders in
`ios/Classes` and `macos/Classes`). The web app runs the same C as
WebAssembly, `web/circuit_engine.wasm` (one thread, no imports, in a Web
Worker: `web/circuit_engine_worker.js`); that one small binary is committed,
rebuilt with `tool/build_circuit_wasm.sh` after any change here, and checked
against the Dart path in a browser by `tool/web_circuit_bench.sh` and, for
abnn, against pinned native outputs by `tool/web_abnn_bench.sh`. Rationale and
numbers: `ml/circuits/README.md`.

For `flutter test` on the host, build it once:

    cmake -S packages/circuit_engine/src -B packages/circuit_engine/src/build
    cmake --build packages/circuit_engine/src/build
