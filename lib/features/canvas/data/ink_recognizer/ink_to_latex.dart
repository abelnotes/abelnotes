// The transformer forward pass, in Dart.
//
// Mirrors ml/src/model.py exactly; the parity test checks that claim against
// reference tensors from PyTorch rather than trusting it. Two shortcuts are
// legitimate here and taken:
//
//  * **No masks.** Training batches padded short inks and masked the padding
//    out. The app recognises one selection at a time, so every position is real
//    and the mask is all-ones — which in the Python encoder multiplies the
//    features by 1 and adds nothing. Batch-1 inference simply has no padding to
//    describe.
//
//  * **No batching.** One ink per call, which keeps every buffer here
//    two-dimensional and the indexing readable.
//
// One thing is *not* a shortcut but a necessary optimisation: the decoder's
// cross-attention keys and values depend only on the encoder memory, so they are
// computed once per recognition instead of once per token. Recomputing them per
// step would cost 2 × nMemory × d² per layer per token — with 80 memory
// positions, 4 layers and 20 tokens that is ~840 MFLOP, more than the entire
// encoder. The self-attention KV cache exists for the same reason at a smaller
// scale: without it, emitting token t re-projects the whole prefix.

import 'dart:math' as math;
import 'dart:typed_data';

import '../circuit_recognizer/native_engine.dart';
import 'ink_features.dart';
import 'model_file.dart';
import 'ops.dart';

/// Per-layer weights of one attention block.
class _Attention {
  _Attention(ModelFile f, String prefix)
      : qW = f['$prefix.q_proj.weight'].floats,
        qB = f['$prefix.q_proj.bias'].floats,
        kW = f['$prefix.k_proj.weight'].floats,
        vW = f['$prefix.v_proj.weight'].floats,
        vB = f['$prefix.v_proj.bias'].floats,
        oW = f['$prefix.out_proj.weight'].floats,
        oB = f['$prefix.out_proj.bias'].floats;

  final Float32List qW, qB, kW, vW, vB, oW, oB;
  // k_proj is built without a bias in the Python model: a bias on the keys adds
  // the same constant to every score in a row, which softmax cancels.
}

class _FeedForward {
  _FeedForward(ModelFile f, String prefix)
      : upW = f['$prefix.0.weight'].floats,
        upB = f['$prefix.0.bias'].floats,
        downW = f['$prefix.3.weight'].floats,
        downB = f['$prefix.3.bias'].floats;
  final Float32List upW, upB, downW, downB;
}

class _Norm {
  _Norm(ModelFile f, String prefix)
      : gamma = f['$prefix.weight'].floats,
        beta = f['$prefix.bias'].floats;
  final Float32List gamma, beta;
}

class _EncoderLayer {
  _EncoderLayer(ModelFile f, int i)
      : norm1 = _Norm(f, 'encoder.layers.$i.norm1'),
        attn = _Attention(f, 'encoder.layers.$i.attn'),
        norm2 = _Norm(f, 'encoder.layers.$i.norm2'),
        ff = _FeedForward(f, 'encoder.layers.$i.ff');
  final _Norm norm1, norm2;
  final _Attention attn;
  final _FeedForward ff;
}

class _DecoderLayer {
  _DecoderLayer(ModelFile f, int i)
      : norm1 = _Norm(f, 'decoder.layers.$i.norm1'),
        selfAttn = _Attention(f, 'decoder.layers.$i.self_attn'),
        norm2 = _Norm(f, 'decoder.layers.$i.norm2'),
        crossAttn = _Attention(f, 'decoder.layers.$i.cross_attn'),
        norm3 = _Norm(f, 'decoder.layers.$i.norm3'),
        ff = _FeedForward(f, 'decoder.layers.$i.ff');
  final _Norm norm1, norm2, norm3;
  final _Attention selfAttn, crossAttn;
  final _FeedForward ff;
}

/// Encoder output: `memory` is [positions, dModel].
class EncodedInk {
  EncodedInk(this.memory, this.positions);
  final Float32List memory;
  final int positions;
}

/// Loaded model, ready to run. Construct once and reuse; loading widens ~7.8M
/// float16 weights, which is not something to redo per recognition.
class InkToLatexModel {
  InkToLatexModel._(this._file, this.config, this.vocab, this.bosId, this.eosId,
      this._encoderLayers, this._decoderLayers);

  factory InkToLatexModel.fromFile(ModelFile file) {
    final config = file.config;
    if (config == null) throw ModelFileException('file has no config; not a weights file');
    // Where the C engine is there, its dense layers read the weights in place.
    final native = NativeMath.instance;
    if (native != null) file.moveFloats(native.adopt);
    return InkToLatexModel._(
      file,
      config,
      file.vocab ?? const [],
      file.bosId,
      file.eosId,
      List.generate(config.nEncoderLayers, (i) => _EncoderLayer(file, i), growable: false),
      List.generate(config.nDecoderLayers, (i) => _DecoderLayer(file, i), growable: false),
    );
  }

  final ModelFile _file;
  final ModelConfig config;
  final List<String> vocab;
  final int bosId;
  final int eosId;
  final List<_EncoderLayer> _encoderLayers;
  final List<_DecoderLayer> _decoderLayers;

  // ── Encoder ──

  /// Runs the conv stem, positions and encoder layers over [features].
  EncodedInk encode(InkFeatures features) {
    final d = config.dModel;
    var x = _stem(features);
    var positions = x.length ~/ d;
    addPositions(x, m: positions, n: d);

    final scratch = Float32List(positions * d);
    final ffUp = Float32List(positions * config.dFf);
    for (final layer in _encoderLayers) {
      _selfAttentionFull(layer.attn, layer.norm1, x, scratch, positions);
      _feedForward(layer.ff, layer.norm2, x, scratch, ffUp, positions);
    }
    layerNorm(x, _file['encoder.norm.weight'].floats, _file['encoder.norm.bias'].floats,
        m: positions, n: d);
    return EncodedInk(x, positions);
  }

  /// Two strided convolutions with GELU, kernel 5 and padding 2.
  ///
  /// Each output position is computed as a single [linear] call over the
  /// gathered receptive field: PyTorch stores a Conv1d weight as
  /// [outChannels, inChannels, kernel], which flattened is exactly
  /// [outChannels, inChannels * kernel] — so gathering the window in
  /// channel-major, kernel-minor order lets the convolution reuse the matmul
  /// kernel with no repacking of the weights.
  Float32List _stem(InkFeatures features) {
    var data = features.values;
    var length = features.pointCount;
    var inChannels = config.nFeatures;

    for (var s = 0; s < config.stemStrides.length; s++) {
      final stride = config.stemStrides[s];
      // Layer index inside nn.Sequential(conv, gelu, conv, gelu).
      final w = _file['encoder.stem.${s * 2}.weight'].floats;
      final b = _file['encoder.stem.${s * 2}.bias'].floats;
      final outChannels = config.dModel;
      final outLength = ((length - 1) ~/ stride) + 1;

      final window = Float32List(inChannels * 5);
      final out = Float32List(outLength * outChannels);
      for (var t = 0; t < outLength; t++) {
        final centre = t * stride - 2; // padding 2
        for (var c = 0; c < inChannels; c++) {
          for (var k = 0; k < 5; k++) {
            final src = centre + k;
            window[c * 5 + k] =
                (src < 0 || src >= length) ? 0.0 : data[src * inChannels + c];
          }
        }
        // A view onto this output position, because linear() always writes its
        // single row at offset 0 of whatever it is given. Writing into `out`
        // directly and copying afterwards would clobber the previous position.
        linear(
          window,
          w,
          b,
          Float32List.sublistView(out, t * outChannels, (t + 1) * outChannels),
          m: 1,
          k: inChannels * 5,
          n: outChannels,
        );
      }
      gelu(out, out.length);
      data = out;
      length = outLength;
      inChannels = outChannels;
    }
    return data;
  }

  /// Pre-norm self-attention over the whole sequence, added into [x] in place.
  void _selfAttentionFull(
      _Attention attn, _Norm norm, Float32List x, Float32List scratch, int t) {
    final d = config.dModel;
    final h = config.nHeads;
    final dh = config.dHead;

    scratch.setRange(0, t * d, x);
    layerNorm(scratch, norm.gamma, norm.beta, m: t, n: d);

    final q = Float32List(t * d);
    final k = Float32List(t * d);
    final v = Float32List(t * d);
    linear(scratch, attn.qW, attn.qB, q, m: t, k: d, n: d);
    linear(scratch, attn.kW, null, k, m: t, k: d, n: d);
    linear(scratch, attn.vW, attn.vB, v, m: t, k: d, n: d);

    final scale = 1.0 / math.sqrt(dh.toDouble());
    final scores = Float32List(t);
    final context = Float32List(t * d);
    for (var head = 0; head < h; head++) {
      final off = head * dh;
      for (var i = 0; i < t; i++) {
        for (var j = 0; j < t; j++) {
          var dot = 0.0;
          for (var c = 0; c < dh; c++) {
            dot += q[i * d + off + c] * k[j * d + off + c];
          }
          scores[j] = dot * scale;
        }
        softmax(scores, 0, t);
        final cBase = i * d + off;
        for (var j = 0; j < t; j++) {
          final p = scores[j];
          if (p == 0.0) continue;
          final vBase = j * d + off;
          for (var c = 0; c < dh; c++) {
            context[cBase + c] += p * v[vBase + c];
          }
        }
      }
    }

    final projected = Float32List(t * d);
    linear(context, attn.oW, attn.oB, projected, m: t, k: d, n: d);
    for (var i = 0; i < t * d; i++) {
      x[i] += projected[i];
    }
  }

  /// Pre-norm feed-forward, added into [x] in place.
  void _feedForward(_FeedForward ff, _Norm norm, Float32List x, Float32List scratch,
      Float32List up, int t) {
    final d = config.dModel;
    final dFf = config.dFf;
    scratch.setRange(0, t * d, x);
    layerNorm(scratch, norm.gamma, norm.beta, m: t, n: d);
    linear(scratch, ff.upW, ff.upB, up, m: t, k: d, n: dFf);
    gelu(up, t * dFf);
    final down = Float32List(t * d);
    linear(up, ff.downW, ff.downB, down, m: t, k: dFf, n: d);
    for (var i = 0; i < t * d; i++) {
      x[i] += down[i];
    }
  }

  // ── Decoder ──

  /// Greedy decode. Returns token ids without BOS or EOS.
  ///
  /// Greedy rather than beam by measurement, not by laziness: on the MathWriting
  /// test split a width-4 beam bought +0.65 ExpRate, which does not pay for four
  /// times the work on a phone.
  /// [probs], when given, receives the softmax probability of each chosen
  /// token, the end token included.
  List<int> decode(EncodedInk encoded, {int? maxLength, List<double>? probs}) {
    final limit = math.min(maxLength ?? config.maxTargetLen, config.maxTargetLen);
    final state = _DecodeState(this, encoded);

    final tokens = <int>[];
    var token = bosId;
    for (var step = 0; step < limit; step++) {
      final logits = state.step(token, step);
      final next = argmax(logits, 0, config.nVocab);
      if (probs != null) {
        var sum = 0.0;
        for (var i = 0; i < config.nVocab; i++) {
          sum += math.exp(logits[i] - logits[next]);
        }
        probs.add(1 / sum);
      }
      if (next == eosId) break;
      tokens.add(next);
      token = next;
    }
    return tokens;
  }

  /// Joins token ids back into renderable LaTeX.
  ///
  /// A space goes between a backslash command and a following letter, because
  /// `\int` then `x` concatenated is `\intx`, a command that does not exist and
  /// will not render. Roughly one output in five needs it — 18.9% of validation
  /// labels contain a command followed by a letter. Must stay in step with
  /// `detokenize` in ml/src/vocab.py.
  String detokenize(List<int> ids) {
    final buffer = StringBuffer();
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (id < 0 || id >= vocab.length) continue;
      final token = vocab[id];
      buffer.write(token);
      if (i + 1 < ids.length) {
        final next = ids[i + 1];
        if (next >= 0 && next < vocab.length && _isCommand(token) && _startsWithLetter(vocab[next])) {
          buffer.write(' ');
        }
      }
    }
    return buffer.toString();
  }

  static bool _isCommand(String token) {
    if (token.length < 2 || !token.startsWith(r'\')) return false;
    for (var i = 1; i < token.length; i++) {
      if (!_isLetter(token.codeUnitAt(i))) return false;
    }
    return true;
  }

  static bool _startsWithLetter(String token) =>
      token.isNotEmpty && _isLetter(token.codeUnitAt(0));

  static bool _isLetter(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  Float32List get _embedding => _file['decoder.embed.weight'].floats;
  Float32List get _headBias => _file['decoder.head.bias'].floats;
}

/// Mutable per-recognition decoder state: the self-attention KV cache and the
/// precomputed cross-attention keys and values.
class _DecodeState {
  _DecodeState(this._model, this._encoded) {
    final cfg = _model.config;
    final d = cfg.dModel;
    final nMem = _encoded.positions;
    final layers = _model._decoderLayers;

    _crossK = List.generate(layers.length, (_) => Float32List(nMem * d), growable: false);
    _crossV = List.generate(layers.length, (_) => Float32List(nMem * d), growable: false);
    for (var i = 0; i < layers.length; i++) {
      // The encoder memory is already normalised by encoder.norm, and the Python
      // cross-attention consumes `memory` directly, so no norm is applied here.
      linear(_encoded.memory, layers[i].crossAttn.kW, null, _crossK[i],
          m: nMem, k: d, n: d);
      linear(_encoded.memory, layers[i].crossAttn.vW, layers[i].crossAttn.vB, _crossV[i],
          m: nMem, k: d, n: d);
    }

    final cap = cfg.maxTargetLen;
    _selfK = List.generate(layers.length, (_) => Float32List(cap * d), growable: false);
    _selfV = List.generate(layers.length, (_) => Float32List(cap * d), growable: false);
    _logits = Float32List(cfg.nVocab);
  }

  final InkToLatexModel _model;
  final EncodedInk _encoded;
  late final List<Float32List> _crossK, _crossV, _selfK, _selfV;
  late final Float32List _logits;

  /// Runs one decoder step for [token] at absolute position [position].
  Float32List step(int token, int position) {
    final cfg = _model.config;
    final d = cfg.dModel;
    final h = cfg.nHeads;
    final dh = cfg.dHead;
    final nMem = _encoded.positions;
    final cached = position + 1; // this token's key/value included

    // Embedding, scaled as in the Python decoder, plus the absolute position.
    final x = Float32List(d);
    final embedScale = math.sqrt(d.toDouble());
    final emb = _model._embedding;
    for (var i = 0; i < d; i++) {
      x[i] = emb[token * d + i] * embedScale;
    }
    addPositions(x, m: 1, n: d, start: position);

    final normed = Float32List(d);
    final q = Float32List(d);
    final scoresSelf = Float32List(cfg.maxTargetLen);
    final scoresCross = Float32List(nMem);
    final context = Float32List(d);
    final projected = Float32List(d);
    final up = Float32List(cfg.dFf);
    final scale = 1.0 / math.sqrt(dh.toDouble());

    for (var l = 0; l < _model._decoderLayers.length; l++) {
      final layer = _model._decoderLayers[l];

      // ── masked self-attention, over the cache plus this token ──
      normed.setRange(0, d, x);
      layerNorm(normed, layer.norm1.gamma, layer.norm1.beta, m: 1, n: d);
      linear(normed, layer.selfAttn.qW, layer.selfAttn.qB, q, m: 1, k: d, n: d);
      // Append this step's key and value at slot `position`. No causal mask is
      // needed: the query is the newest token, so every cached position is a
      // legitimate one to attend to.
      final kSlice = Float32List.sublistView(_selfK[l], position * d, (position + 1) * d);
      final vSlice = Float32List.sublistView(_selfV[l], position * d, (position + 1) * d);
      linear(normed, layer.selfAttn.kW, null, kSlice, m: 1, k: d, n: d);
      linear(normed, layer.selfAttn.vW, layer.selfAttn.vB, vSlice, m: 1, k: d, n: d);
      _attendSingleQuery(q, _selfK[l], _selfV[l], cached, h, dh, d, scale, scoresSelf, context);
      linear(context, layer.selfAttn.oW, layer.selfAttn.oB, projected, m: 1, k: d, n: d);
      for (var i = 0; i < d; i++) {
        x[i] += projected[i];
      }

      // ── cross-attention over the encoder memory ──
      normed.setRange(0, d, x);
      layerNorm(normed, layer.norm2.gamma, layer.norm2.beta, m: 1, n: d);
      linear(normed, layer.crossAttn.qW, layer.crossAttn.qB, q, m: 1, k: d, n: d);
      _attendSingleQuery(
          q, _crossK[l], _crossV[l], nMem, h, dh, d, scale, scoresCross, context);
      linear(context, layer.crossAttn.oW, layer.crossAttn.oB, projected, m: 1, k: d, n: d);
      for (var i = 0; i < d; i++) {
        x[i] += projected[i];
      }

      // ── feed-forward ──
      normed.setRange(0, d, x);
      layerNorm(normed, layer.norm3.gamma, layer.norm3.beta, m: 1, n: d);
      linear(normed, layer.ff.upW, layer.ff.upB, up, m: 1, k: d, n: cfg.dFf);
      gelu(up, cfg.dFf);
      linear(up, layer.ff.downW, layer.ff.downB, projected, m: 1, k: cfg.dFf, n: d);
      for (var i = 0; i < d; i++) {
        x[i] += projected[i];
      }
    }

    layerNorm(x, _model._file['decoder.norm.weight'].floats,
        _model._file['decoder.norm.bias'].floats,
        m: 1, n: d);
    // The output head is tied to the token embedding, so the embedding matrix is
    // reused here as [nVocab, dModel] instead of shipping a second copy.
    linear(x, emb, _model._headBias, _logits, m: 1, k: d, n: cfg.nVocab);
    return _logits;
  }

  /// One query row against `count` cached keys/values, all heads. Writes
  /// [context], which is zeroed first.
  static void _attendSingleQuery(
    Float32List q,
    Float32List keys,
    Float32List values,
    int count,
    int nHeads,
    int dHead,
    int d,
    double scale,
    Float32List scores,
    Float32List context,
  ) {
    context.fillRange(0, d, 0.0);
    for (var head = 0; head < nHeads; head++) {
      final off = head * dHead;
      for (var j = 0; j < count; j++) {
        var dot = 0.0;
        final kBase = j * d + off;
        for (var c = 0; c < dHead; c++) {
          dot += q[off + c] * keys[kBase + c];
        }
        scores[j] = dot * scale;
      }
      softmax(scores, 0, count);
      for (var j = 0; j < count; j++) {
        final p = scores[j];
        if (p == 0.0) continue;
        final vBase = j * d + off;
        for (var c = 0; c < dHead; c++) {
          context[off + c] += p * values[vBase + c];
        }
      }
    }
  }
}
