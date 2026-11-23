// Small value types shared by the editor screen: image size, native pen
// barrel button, pen hover hint.

class Dims {
  final int width, height;
  Dims(this.width, this.height);
}

/// Identifies which side button of the pen triggered the native
/// barrel override. Mirrors the two `penFlags` bits the C++ runner
/// reads — see `PenInputChannel` doc comment.
enum NativeBarrel { upper, lower }

/// What a hovering pen previews: eraser radius or lasso badge.
enum PenHoverHint { eraser, lasso }
