// Does pure-Dart inference clear the latency bar, or do we need a native runtime?
//
// The model planned for ink -> LaTeX is a ~10M-parameter transformer. Its cost is
// dominated by dense matrix multiplies, so the whole runtime question reduces to
// one number: how many GFLOP/s of f32 matmul does Dart sustain on the target
// hardware. Everything else (layernorm, softmax, gelu) is a few percent.
//
// FLOP budget for one recognition, at d_model=256, 4+4 layers, 128 memory
// positions after the encoder's 4x downsample, ~60 decoded tokens:
//
//   encoder, per layer:  qkvo   2 * 128 * 256 * 256 * 4  =  67 MFLOP
//                        ffn    2 * 128 * 256 * 1024 * 2 = 134 MFLOP
//                        attn   2 * 128 * 128 * 256 * 2  =  17 MFLOP
//   encoder total:       4 layers * 218 MFLOP            = 872 MFLOP
//   decoder, per step:   self+cross+ffn at 1 query row   =  ~3 MFLOP
//   decoder total:       60 steps * 4 layers * 3 MFLOP   = 720 MFLOP
//   ----------------------------------------------------------------
//   ~1.6 GFLOP per recognition
//
// So at 1 GFLOP/s a recognition takes ~1.6s; at 4 GFLOP/s, ~0.4s. The bar: this
// runs on an explicit user action ("convert selection to LaTeX"), never per
// stroke, so ~300ms is comfortable, ~1s is acceptable, >3s is not.
//
// Three kernels are compared because the gap between them decides how much work
// the Dart port is:
//   naive     — textbook i/j/k loops, the honest floor
//   rowmajor  — same maths, loop order swapped so both reads walk memory
//               forwards; this is usually most of the available speedup
//   simd      — Float32x4 over the packed accumulator, 4 lanes per step
//
// Run JIT:  dart run bench.dart
// Run AOT:  dart compile exe bench.dart -o bench && ./bench
// AOT is the number that matters — a Flutter release build is AOT.

import 'dart:math' as math;
import 'dart:typed_data';

/// C[m,n] = A[m,k] * B[k,n], textbook order. B is walked down a column, so
/// every inner step jumps `n` floats — a cache miss per multiply once the
/// matrices leave L2.
void matmulNaive(Float32List a, Float32List b, Float32List c, int m, int k, int n) {
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < n; j++) {
      var sum = 0.0;
      for (var p = 0; p < k; p++) {
        sum += a[i * k + p] * b[p * n + j];
      }
      c[i * n + j] = sum;
    }
  }
}

/// Same result, k in the middle: for each element of A, accumulate its scaled
/// row of B into the output row. Both B and C are read/written sequentially.
void matmulRowMajor(Float32List a, Float32List b, Float32List c, int m, int k, int n) {
  c.fillRange(0, m * n, 0.0);
  for (var i = 0; i < m; i++) {
    final crow = i * n;
    for (var p = 0; p < k; p++) {
      final av = a[i * k + p];
      if (av == 0.0) continue;
      final brow = p * n;
      for (var j = 0; j < n; j++) {
        c[crow + j] += av * b[brow + j];
      }
    }
  }
}

/// Row-major order again, but the inner accumulate runs four columns at a time
/// through Float32x4. Requires n % 4 == 0, which every dimension in this model
/// satisfies (256, 1024, and a vocabulary padded to a multiple of 4).
void matmulSimd(Float32List a, Float32List b, Float32List c, int m, int k, int n) {
  final n4 = n >> 2;
  final bv = Float32x4List.view(b.buffer, b.offsetInBytes, k * n4);
  final cv = Float32x4List.view(c.buffer, c.offsetInBytes, m * n4);
  for (var i = 0; i < m * n4; i++) {
    cv[i] = Float32x4.zero();
  }
  for (var i = 0; i < m; i++) {
    final crow = i * n4;
    for (var p = 0; p < k; p++) {
      final av = a[i * k + p];
      if (av == 0.0) continue;
      final splat = Float32x4.splat(av);
      final brow = p * n4;
      for (var j = 0; j < n4; j++) {
        cv[crow + j] += splat * bv[brow + j];
      }
    }
  }
}

Float32List randomMatrix(int n, math.Random rng) =>
    Float32List.fromList(List<double>.generate(n, (_) => rng.nextDouble() - 0.5));

typedef Kernel = void Function(Float32List, Float32List, Float32List, int, int, int);

/// Times `kernel` on an (m,k)x(k,n) product, reporting sustained GFLOP/s.
/// Runs a warmup pass first so the JIT has optimized the loop before timing,
/// then repeats until at least [minMillis] have elapsed so a fast kernel is not
/// measured against clock granularity.
double benchmark(Kernel kernel, int m, int k, int n, {int minMillis = 400}) {
  final rng = math.Random(7);
  final a = randomMatrix(m * k, rng);
  final b = randomMatrix(k * n, rng);
  final c = Float32List(m * n);

  kernel(a, b, c, m, k, n);

  final flopPerCall = 2.0 * m * k * n;
  final sw = Stopwatch()..start();
  var calls = 0;
  while (sw.elapsedMilliseconds < minMillis) {
    kernel(a, b, c, m, k, n);
    calls++;
  }
  sw.stop();
  return (flopPerCall * calls) / (sw.elapsedMicroseconds * 1000.0);
}

/// Confirms the three kernels agree, so a fast one is not fast by being wrong.
void checkAgreement() {
  const m = 37, k = 53, n = 64; // deliberately not round, except n for SIMD
  final rng = math.Random(1);
  final a = randomMatrix(m * k, rng);
  final b = randomMatrix(k * n, rng);
  final ref = Float32List(m * n);
  matmulNaive(a, b, ref, m, k, n);

  for (final entry in {'rowmajor': matmulRowMajor, 'simd': matmulSimd}.entries) {
    final got = Float32List(m * n);
    entry.value(a, b, got, m, k, n);
    var worst = 0.0;
    for (var i = 0; i < ref.length; i++) {
      worst = math.max(worst, (ref[i] - got[i]).abs());
    }
    // f32 accumulation in a different order gives a different rounding, so the
    // tolerance is on the order of k * eps * magnitude, not exact equality.
    final status = worst < 1e-3 ? 'ok' : 'MISMATCH';
    print('  ${entry.key.padRight(9)} max abs diff vs naive ${worst.toStringAsExponential(2)}  $status');
  }
}

void main() {
  print('kernel agreement');
  checkAgreement();

  // Shapes taken straight from the planned model, so the numbers need no
  // extrapolation across matrix size.
  const shapes = [
    ('enc qkvo   128x256x256', 128, 256, 256),
    ('enc ffn up 128x256x1024', 128, 256, 1024),
    ('enc ffn dn 128x1024x256', 128, 1024, 256),
    ('dec step     1x256x256', 1, 256, 256),
    ('vocab head   1x256x320', 1, 256, 320),
  ];

  print('\nsustained GFLOP/s');
  print('  ${'shape'.padRight(24)} ${'naive'.padLeft(8)} ${'rowmajor'.padLeft(9)} ${'simd'.padLeft(8)}');
  final best = <String, double>{};
  for (final (name, m, k, n) in shapes) {
    final gNaive = benchmark(matmulNaive, m, k, n);
    final gRow = benchmark(matmulRowMajor, m, k, n);
    final gSimd = benchmark(matmulSimd, m, k, n);
    best[name] = math.max(gRow, gSimd);
    print('  ${name.padRight(24)} ${gNaive.toStringAsFixed(2).padLeft(8)}'
        ' ${gRow.toStringAsFixed(2).padLeft(9)} ${gSimd.toStringAsFixed(2).padLeft(8)}');
  }

  // Translate the encoder-shaped throughput into the end-to-end latency that
  // actually decides the runtime question.
  final encThroughput = best['enc ffn up 128x256x1024']!;
  const totalGflop = 1.6;
  final seconds = totalGflop / encThroughput;
  print('\nprojected latency for one recognition (~${totalGflop}GFLOP)');
  print('  this machine, AOT-or-JIT as run:  ${(seconds * 1000).toStringAsFixed(0)} ms');
  print('  mid-range phone (assume 3x slower): ${(seconds * 3000).toStringAsFixed(0)} ms');
  print('\nbar: <300ms comfortable, <1s acceptable, >3s means use a native runtime');
}
