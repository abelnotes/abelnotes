import 'dart:typed_data';

/// No native engine on this platform.
class NativeEngine {
  NativeEngine._();

  static NativeEngine? open() => null;

  bool conv(int input, int output, int cin, int cout, int k, int s, int p, int g, bool act, Float32List w,
          int wStride, Float32List b) =>
      false;
  bool add(int a, int b, int output) => false;
  bool concat(List<int> inputs, int output) => false;
  bool split(int input, List<int> outputs, List<int> sizes) => false;
  bool maxpool(int input, int output, int k, int p) => false;
  bool upsample(int input, int output, int scale) => false;
  bool attn(int input, int outX, int outV, int heads, int keyDim, int headDim, double scale) => false;
  Float32List? run(Float32List gray, int h, int w, List<int> want, int outLen) => null;
  void dispose() {}
}

/// No native pixel passes on this platform.
class NativeImage {
  NativeImage._();

  static bool forceDart = false;

  static NativeImage? open() => null;

  ({Uint8List rgb, Uint8List gray, Uint8List ink, Uint8List skel, Int32List dist, bool tinted}) tracePrep(
          Uint8List rgba, int w, int h, int cw, int ch) =>
      throw UnsupportedError('no native engine');

  ({List<(Float64List, double, int)> strokes, Uint8List ink}) trace(
          Uint8List rgba, int w, int h, int cw, int ch, double s) =>
      throw UnsupportedError('no native engine');

  Float32List rasterizeInk(Uint8List ink, int w, int h, double inkScale, double originX, double originY, double scale,
          int rw, int rh) =>
      throw UnsupportedError('no native engine');

  ({Uint8List alpha, int x0, int y0, int x1, int y1, int kept}) leftover(
          Uint8List rgba, int w, int h, List<(Float64List, double)> cut) =>
      throw UnsupportedError('no native engine');
}
