// Reader for the ABLM container written by ml/src/export_dart.py.
//
//     magic     4 bytes   "ABLM"
//     version   uint32
//     jsonLen   uint32
//     json      bytes     {"kind": "...", "config": {...}, "vocab": [...], "tensors": [...]}
//     payload   bytes     every tensor, concatenated, each 8-byte aligned
//
// Weights are stored as float16 and widened here. Dart has no float16 type, so
// the conversion is done by hand — about twenty lines, in exchange for halving
// the file that ships with the app. Rounding the trained weights through
// float16 left ExpRate and CER unchanged on the validation split.

import 'dart:convert';
import 'dart:typed_data';

const _magic = 'ABLM';
const _supportedVersion = 1;

class ModelFileException implements Exception {
  ModelFileException(this.message);
  final String message;
  @override
  String toString() => 'ModelFileException: $message';
}

/// Configuration of the exported model, as recorded at training time.
class ModelConfig {
  ModelConfig({
    required this.nVocab,
    required this.nFeatures,
    required this.dModel,
    required this.nHeads,
    required this.dFf,
    required this.nEncoderLayers,
    required this.nDecoderLayers,
    required this.maxTargetLen,
    required this.stemStrides,
  });

  factory ModelConfig.fromJson(Map<String, dynamic> json) => ModelConfig(
        nVocab: json['n_vocab'] as int,
        nFeatures: json['n_features'] as int,
        dModel: json['d_model'] as int,
        nHeads: json['n_heads'] as int,
        dFf: json['d_ff'] as int,
        nEncoderLayers: json['n_encoder_layers'] as int,
        nDecoderLayers: json['n_decoder_layers'] as int,
        maxTargetLen: json['max_target_len'] as int,
        stemStrides:
            (json['stem_strides'] as List<dynamic>).map((e) => e as int).toList(growable: false),
      );

  final int nVocab;
  final int nFeatures;
  final int dModel;
  final int nHeads;
  final int dFf;
  final int nEncoderLayers;
  final int nDecoderLayers;
  final int maxTargetLen;
  final List<int> stemStrides;

  int get dHead => dModel ~/ nHeads;

  /// Total downsampling applied by the conv stem, i.e. how many input points
  /// each encoder position covers.
  int get downsample => stemStrides.fold(1, (a, b) => a * b);
}

/// A named tensor: its shape and its data widened to float32, or int32.
class Tensor {
  Tensor(this.name, this.shape, this.f32, this.i32, [this._widen]);
  final String name;
  final List<int> shape;
  Float32List? f32;
  final Int32List? i32;

  /// Pending float16 widening: done on first use, so loading a model costs no
  /// pass over its weights.
  Float32List Function()? _widen;

  bool get hasFloats => f32 != null || _widen != null;

  Float32List get floats {
    final w = _widen;
    if (w != null) {
      f32 = w();
      _widen = null;
    }
    final f = f32;
    if (f == null) throw ModelFileException('$name is not a float tensor');
    return f;
  }

  Int32List get ints {
    final i = i32;
    if (i == null) throw ModelFileException('$name is not an int tensor');
    return i;
  }

  int get length => shape.isEmpty ? 0 : shape.reduce((a, b) => a * b);
}

/// A parsed ABLM file: header metadata plus every tensor by name.
class ModelFile {
  ModelFile._(this.kind, this.header, this.config, this.vocab, this.bosId, this.eosId,
      this.padId, this._tensors);

  static ModelFile parse(Uint8List bytes) {
    if (bytes.length < 12) throw ModelFileException('file too short');
    if (String.fromCharCodes(bytes.sublist(0, 4)) != _magic) {
      throw ModelFileException('bad magic; not an ABLM file');
    }
    final head = ByteData.sublistView(bytes, 4, 12);
    final version = head.getUint32(0, Endian.little);
    if (version != _supportedVersion) {
      throw ModelFileException('unsupported version $version, expected $_supportedVersion');
    }
    final jsonLen = head.getUint32(4, Endian.little);
    final payloadStart = 12 + jsonLen;
    if (bytes.length < payloadStart) throw ModelFileException('header truncated');

    final header =
        jsonDecode(utf8.decode(bytes.sublist(12, payloadStart))) as Map<String, dynamic>;

    final tensors = <String, Tensor>{};
    for (final entry in header['tensors'] as List<dynamic>) {
      final e = entry as Map<String, dynamic>;
      final name = e['name'] as String;
      final dtype = e['dtype'] as String;
      final shape = (e['shape'] as List<dynamic>).map((v) => v as int).toList(growable: false);
      final offset = payloadStart + (e['offset'] as int);
      final byteCount = e['bytes'] as int;
      if (offset + byteCount > bytes.length) {
        throw ModelFileException('tensor $name runs past end of file');
      }
      switch (dtype) {
        case 'f16':
          tensors[name] = Tensor(name, shape, null, null,
              () => _widenFloat16(bytes, offset, byteCount >> 1));
        case 'f32':
          tensors[name] = Tensor(name, shape, _readFloat32(bytes, offset, byteCount >> 2), null);
        case 'i32':
          tensors[name] = Tensor(name, shape, null, _readInt32(bytes, offset, byteCount >> 2));
        default:
          throw ModelFileException('unknown dtype $dtype for tensor $name');
      }
    }

    final vocabJson = header['vocab'] as List<dynamic>?;
    final config = header['config'] as Map<String, dynamic>?;
    return ModelFile._(
      header['kind'] as String? ?? 'weights',
      header,
      config == null ? null : ModelConfig.fromJson(config),
      vocabJson?.map((e) => e as String).toList(growable: false),
      header['bos_id'] as int? ?? 1,
      header['eos_id'] as int? ?? 2,
      header['pad_id'] as int? ?? 0,
      tensors,
    );
  }

  /// [parse] plus the weight widening, done in slices that yield to the event
  /// loop so a model load on the UI thread does not drop frames.
  static Future<ModelFile> parseAsync(Uint8List bytes) async {
    final file = parse(bytes);
    var pending = 0;
    for (final t in file._tensors.values) {
      if (!t.hasFloats) continue;
      pending += t.floats.length;
      if (pending > (1 << 19)) {
        pending = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    return file;
  }

  final String kind;

  /// The decoded JSON header, verbatim. The typed fields below cover what
  /// inference needs; this is here for the rest — a test-vector file's `step`,
  /// `labels` and `predictions`, and the `storage_dtype` a parity test needs to
  /// pick its tolerance.
  final Map<String, dynamic> header;

  final ModelConfig? config;
  final List<String>? vocab;
  final int bosId;
  final int eosId;
  final int padId;
  final Map<String, Tensor> _tensors;

  Iterable<String> get names => _tensors.keys;

  bool has(String name) => _tensors.containsKey(name);

  /// Replaces every float tensor with [move] of it (into native memory, for
  /// the C dense layers), once, before any layer holds a reference.
  void moveFloats(Float32List Function(Float32List) move) {
    for (final t in _tensors.values) {
      if (t.hasFloats) t.f32 = move(t.floats);
    }
  }

  Tensor operator [](String name) {
    final t = _tensors[name];
    if (t == null) {
      throw ModelFileException('missing tensor "$name"; file has ${_tensors.length} tensors');
    }
    return t;
  }

  /// Reads `count` float32 values starting at `byteOffset` into a fresh list.
  ///
  /// Copied rather than viewed. A view would be free, but its byte offset is
  /// whatever the file put it at, and two things object: `Float32List.sublistView`
  /// rejects an offset that is not a multiple of 4, and the SIMD matmul views its
  /// operands as `Float32x4List`, which demands a multiple of 16. The exporter
  /// aligns tensors to 16 *within the payload*, and the payload begins after a
  /// variable-length JSON header, so absolute offsets can be anything. Copying
  /// costs one pass over a tensor at load time and removes the whole class of
  /// alignment failure; the shipped model is f16 anyway, which is always widened
  /// into a fresh list.
  static Float32List _readFloat32(Uint8List bytes, int byteOffset, int count) {
    final src = ByteData.sublistView(bytes, byteOffset, byteOffset + count * 4);
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      out[i] = src.getFloat32(i * 4, Endian.little);
    }
    return out;
  }

  /// Reads `count` int32 values starting at `byteOffset`. Copied, for the
  /// alignment reason given on [_readFloat32].
  static Int32List _readInt32(Uint8List bytes, int byteOffset, int count) {
    final src = ByteData.sublistView(bytes, byteOffset, byteOffset + count * 4);
    final out = Int32List(count);
    for (var i = 0; i < count; i++) {
      out[i] = src.getInt32(i * 4, Endian.little);
    }
    return out;
  }

  /// Widens `count` IEEE 754 binary16 values starting at `byteOffset`.
  ///
  /// Handles the three cases that a naive shift-and-or gets wrong: subnormals
  /// (exponent 0 with a non-zero mantissa, which need renormalising), and
  /// infinity and NaN (exponent 31, which must map to float32's exponent 255
  /// rather than 31 + 112).
  static Float32List _widenFloat16(Uint8List bytes, int byteOffset, int count) {
    final src = ByteData.sublistView(bytes, byteOffset, byteOffset + count * 2);
    final out = Float32List(count);
    final scratch = ByteData(4);
    for (var i = 0; i < count; i++) {
      final h = src.getUint16(i * 2, Endian.little);
      final sign = (h & 0x8000) << 16;
      final exponent = (h >> 10) & 0x1F;
      final mantissa = h & 0x3FF;
      int bits;
      if (exponent == 0) {
        if (mantissa == 0) {
          bits = sign; // signed zero
        } else {
          // Subnormal: shift the mantissa left until its top bit falls out,
          // decrementing the exponent to match, then emit it as a normal float32.
          var m = mantissa;
          var e = -1;
          do {
            m <<= 1;
            e++;
          } while ((m & 0x400) == 0);
          bits = sign | ((112 - e) << 23) | ((m & 0x3FF) << 13);
        }
      } else if (exponent == 0x1F) {
        bits = sign | 0x7F800000 | (mantissa << 13); // inf or NaN
      } else {
        bits = sign | ((exponent + 112) << 23) | (mantissa << 13);
      }
      scratch.setUint32(0, bits, Endian.little);
      out[i] = scratch.getFloat32(0, Endian.little);
    }
    return out;
  }
}
