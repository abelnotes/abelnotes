// Numeric kernels for on-device models.
//
// The circuit detector's dense convolutions are im2col + a matrix product, so
// this file is one well-tuned matmul. It has no dependencies: no FFI, no
// platform channel, no native library, so it runs on every target Flutter
// compiles for. Where packages/circuit_engine is built the detector runs there
// instead (see detector.dart).
//
// Layout convention, chosen to match PyTorch so no weight is ever transposed:
// a Linear's weight arrives as [outFeatures, inFeatures] and the forward pass is
// y = x · Wᵀ. Written as a dot product of row i of x with row j of W, both walk
// their memory forwards, which is what makes the SIMD path below worth having:
// the four-lane accumulate runs about 5x the scalar loop.

import 'dart:typed_data';

/// y[m, n] = x[m, k] · wᵀ + bias, with `w` shaped [n, k] and `bias` length n.
///
/// Pass [bias] as null for an unbiased projection. [out] must have room for
/// m * n floats and is overwritten, not accumulated into.
void linear(
  Float32List x,
  Float32List w,
  Float32List? bias,
  Float32List out, {
  required int m,
  required int k,
  required int n,
}) {
  // The SIMD path indexes rows as (i * k) >> 2, i.e. in units of four floats, so
  // it is only correct when a row boundary *is* a lane boundary: at any other k
  // the row bases would silently truncate and read a fraction of a lane off the
  // start of every row but the first. The alignment checks cover a Float32List
  // that is a view into a larger buffer, which Float32x4List.view rejects unless
  // its byte offset is a multiple of 16.
  if (_isJs) {
    _linearBlocked(x, w, bias, out, m: m, k: k, n: n);
    return;
  }
  if ((k & 3) != 0 || x.offsetInBytes % 16 != 0 || w.offsetInBytes % 16 != 0) {
    _linearScalar(x, w, bias, out, m: m, k: k, n: n);
    return;
  }

  final k4 = k >> 2;
  final tail = k - (k4 << 2);
  final xv = Float32x4List.view(x.buffer, x.offsetInBytes, x.length >> 2);
  final wv = Float32x4List.view(w.buffer, w.offsetInBytes, w.length >> 2);

  for (var i = 0; i < m; i++) {
    final xBase4 = (i * k) >> 2;
    final xBase = i * k;
    for (var j = 0; j < n; j++) {
      final wBase4 = (j * k) >> 2;
      // Four independent accumulators rather than one: a single running sum
      // serialises on the add's latency, while four let the CPU keep several in
      // flight. Worth roughly a third of the throughput on this kernel.
      var a0 = Float32x4.zero();
      var a1 = Float32x4.zero();
      var a2 = Float32x4.zero();
      var a3 = Float32x4.zero();
      var p = 0;
      final unrolled = k4 - (k4 % 4);
      while (p < unrolled) {
        a0 += xv[xBase4 + p] * wv[wBase4 + p];
        a1 += xv[xBase4 + p + 1] * wv[wBase4 + p + 1];
        a2 += xv[xBase4 + p + 2] * wv[wBase4 + p + 2];
        a3 += xv[xBase4 + p + 3] * wv[wBase4 + p + 3];
        p += 4;
      }
      while (p < k4) {
        a0 += xv[xBase4 + p] * wv[wBase4 + p];
        p++;
      }
      final acc = (a0 + a1) + (a2 + a3);
      var sum = acc.x + acc.y + acc.z + acc.w;
      // Unreachable while k is a multiple of 4, which the guard above enforces;
      // kept so the loop reads as a complete dot product.
      for (var t = k - tail; t < k; t++) {
        sum += x[xBase + t] * w[j * k + t];
      }
      out[i * n + j] = bias == null ? sum : sum + bias[j];
    }
  }
}

// Compiled to JavaScript, Float32x4 is emulated with objects: ~25x slower than the scalar loop.
const bool _isJs = identical(0, 0.0);

/// [linear] for JavaScript: 2x2 output blocks, so each load feeds two products.
void _linearBlocked(
  Float32List x,
  Float32List w,
  Float32List? bias,
  Float32List out, {
  required int m,
  required int k,
  required int n,
}) {
  final m2 = m & ~1, n2 = n & ~1;
  for (var i = 0; i < m2; i += 2) {
    final xa = i * k, xb = xa + k;
    for (var j = 0; j < n2; j += 2) {
      final wa = j * k, wb = wa + k;
      var s00 = 0.0, s01 = 0.0, s10 = 0.0, s11 = 0.0;
      for (var p = 0; p < k; p++) {
        final x0 = x[xa + p], x1 = x[xb + p], w0 = w[wa + p], w1 = w[wb + p];
        s00 += x0 * w0;
        s01 += x0 * w1;
        s10 += x1 * w0;
        s11 += x1 * w1;
      }
      final b0 = bias == null ? 0.0 : bias[j], b1 = bias == null ? 0.0 : bias[j + 1];
      out[i * n + j] = s00 + b0;
      out[i * n + j + 1] = s01 + b1;
      out[(i + 1) * n + j] = s10 + b0;
      out[(i + 1) * n + j + 1] = s11 + b1;
    }
  }
  // Odd edges.
  for (var i = 0; i < m; i++) {
    for (var j = (i < m2 ? n2 : 0); j < n; j++) {
      var sum = 0.0;
      for (var p = 0; p < k; p++) {
        sum += x[i * k + p] * w[j * k + p];
      }
      out[i * n + j] = bias == null ? sum : sum + bias[j];
    }
  }
}

/// Plain-scalar [linear], for shapes the four-lane kernel cannot address.
///
/// [linear] for a row length off the SIMD lanes or an unaligned view.
void _linearScalar(
  Float32List x,
  Float32List w,
  Float32List? bias,
  Float32List out, {
  required int m,
  required int k,
  required int n,
}) {
  for (var i = 0; i < m; i++) {
    final xBase = i * k;
    for (var j = 0; j < n; j++) {
      final wBase = j * k;
      var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;
      var p = 0;
      for (; p + 3 < k; p += 4) {
        s0 += x[xBase + p] * w[wBase + p];
        s1 += x[xBase + p + 1] * w[wBase + p + 1];
        s2 += x[xBase + p + 2] * w[wBase + p + 2];
        s3 += x[xBase + p + 3] * w[wBase + p + 3];
      }
      for (; p < k; p++) {
        s0 += x[xBase + p] * w[wBase + p];
      }
      final sum = (s0 + s1) + (s2 + s3);
      out[i * n + j] = bias == null ? sum : sum + bias[j];
    }
  }
}
