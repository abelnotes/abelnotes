# circuit_engine

The circuit tidy-up's CPU engine in C (`src/`): the detector's forward pass
(`circuit_engine.c`) and the picture passes (`image_ink.c`), bound from the
app with dart:ffi. An FFI plugin so each platform's Flutter build compiles it
from source (CMake on Linux, Windows and Android, CocoaPods forwarders in
`ios/Classes` and `macos/Classes`); no binary is committed. Rationale and
numbers: `ml/circuits/README.md`.

For `flutter test` on the host, build it once:

    cmake -S packages/circuit_engine/src -B packages/circuit_engine/src/build
    cmake --build packages/circuit_engine/src/build
