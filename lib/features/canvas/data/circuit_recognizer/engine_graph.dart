import 'dart:typed_data';

/// The op calls that build the detector's graph on an engine: the native
/// library, its WebAssembly build, or a worker running that build.
abstract interface class EngineGraph {
  bool conv(int input, int output, int cin, int cout, int k, int s, int p, int g, bool act, Float32List w,
      int wStride, Float32List b);
  bool add(int a, int b, int output);
  bool concat(List<int> inputs, int output);
  bool split(int input, List<int> outputs, List<int> sizes);
  bool maxpool(int input, int output, int k, int p);
  bool upsample(int input, int output, int scale);
  bool attn(int input, int outX, int outV, int heads, int keyDim, int headDim, double scale);
}
