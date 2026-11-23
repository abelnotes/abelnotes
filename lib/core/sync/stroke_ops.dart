// Stroke delta chunks: what changed on a page, as a small immutable file next
// to its snapshot. Codec, diff and apply; design in README.md, "Stroke deltas".
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:abelnotes/core/notebook/page_codec.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Switches and limits of the stroke delta sync. This release reads chunks
/// and does not write them: writing waits until every device reads them
/// (README.md, "Read on, write off").
class StrokeOps {
  StrokeOps._();

  static const bool _readShipped = true;
  static const bool _writeShipped = false;

  /// List and apply chunks when reading pages.
  static bool read = _readShipped;

  /// Write chunks instead of whole pages where possible (needs [read]).
  static bool write = _writeShipped;

  /// Back to the flags this release ships with.
  @visibleForTesting
  static void restoreDefaults() {
    read = _readShipped;
    write = _writeShipped;
  }

  static bool get writing => read && write;

  /// Live chunks on a page from which the next save compacts it.
  static const int maxLiveChunks = 24;

  /// From this snapshot size on, a save also compacts once its chunks
  /// outgrow the snapshot.
  static const int compactFromBytes = 32 * 1024;

  static const String folder = 'ops/';
  static const String extension = '.abop';
}

/// A chunk in a format newer than this app reads: not damage, never folded.
/// Its message avoids "FormatException", which the pull reads as damage.
class ChunkTooNewException implements Exception {
  const ChunkTooNewException(this.version);
  final int version;
  @override
  String toString() => 'ChunkTooNew: op chunk version $version is newer than this app reads';
}

enum OpKind { add, replace, delete }

class StrokeOp {
  const StrokeOp(this.kind, this.id, [this.element]);
  final OpKind kind;
  final String id;

  /// The element for add and replace, null for delete.
  final ContentElement? element;
}

/// One chunk's content: the ops of one save on one page.
class OpChunk {
  const OpChunk({
    required this.pageId,
    required this.ops,
    this.modifiedAt,
    this.header,
  });

  final String pageId;
  final List<StrokeOp> ops;
  final DateTime? modifiedAt;

  /// The page fields other than content and modifiedAt, when they changed.
  final PageData? header;

  bool get isEmpty => ops.isEmpty && header == null;
}

/// A chunk's name: who wrote it and when, in hybrid Lamport order.
class ChunkId implements Comparable<ChunkId> {
  const ChunkId(this.device, this.clock);
  final String device;
  final int clock;

  String get id => '$device~${clock.toRadixString(36)}';

  static ChunkId? parse(String id) {
    final at = id.indexOf('~');
    if (at <= 0 || at != id.lastIndexOf('~')) return null;
    final clock = int.tryParse(id.substring(at + 1), radix: 36);
    if (clock == null) return null;
    return ChunkId(id.substring(0, at), clock);
  }

  @override
  int compareTo(ChunkId other) => clock != other.clock
      ? clock.compareTo(other.clock)
      : device.compareTo(other.device);

  @override
  bool operator ==(Object other) =>
      other is ChunkId && other.device == device && other.clock == clock;

  @override
  int get hashCode => Object.hash(device, clock);

  @override
  String toString() => id;
}

/// Random device tag for chunk names: 8 base-36 characters.
String newDeviceTag([Random? random]) {
  final r = random ?? Random.secure();
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  return String.fromCharCodes(
      List.generate(8, (_) => digits.codeUnitAt(r.nextInt(36))));
}

/// `page_003.json` + chunk → `page_003~<device>~<clock>.abop`.
String chunkFileName(String pageFile, ChunkId id) =>
    '${_stem(pageFile)}~${id.id}${StrokeOps.extension}';

/// The page file and chunk id of a chunk file name, null for anything else.
({String pageFile, ChunkId id})? parseChunkFileName(String name) {
  if (!name.endsWith(StrokeOps.extension)) return null;
  final base = name.substring(0, name.length - StrokeOps.extension.length);
  final parts = base.split('~');
  if (parts.length != 3 || parts[0].isEmpty) return null;
  final id = ChunkId.parse('${parts[1]}~${parts[2]}');
  if (id == null) return null;
  return (pageFile: '${parts[0]}.json', id: id);
}

String _stem(String pageFile) => pageFile.endsWith('.json')
    ? pageFile.substring(0, pageFile.length - 5)
    : pageFile;

// ── Page versions ──

/// The version of a page with chunks: snapshot etag, then the sorted chunk ids.
String pageVersion(String snapshot, Iterable<ChunkId> chunks) {
  if (chunks.isEmpty) return snapshot;
  final ids = chunks.toList()..sort();
  return '$snapshot|${ids.map((c) => c.id).join(',')}';
}

/// Inverse of [pageVersion]; a bare etag has no chunks.
({String snapshot, List<ChunkId> chunks}) splitPageVersion(String version) {
  final bar = version.indexOf('|');
  if (bar < 0) return (snapshot: version, chunks: const <ChunkId>[]);
  return (
    snapshot: version.substring(0, bar),
    chunks: [
      for (final s in version.substring(bar + 1).split(','))
        if (ChunkId.parse(s) case final id?) id,
    ],
  );
}

// ── Codec ──

const _magic = [0x41, 0x42, 0x4F, 0x50]; // "ABOP"
const _version = 1;

/// Chunk bytes: "ABOP", version, varint header length, JSON header, then the
/// add and replace elements as one page in the page codec.
Uint8List encodeChunk(OpChunk c) {
  final elements = [
    for (final op in c.ops)
      if (op.kind != OpKind.delete) op.element!,
  ];
  final header = <String, Object?>{
    'pageId': c.pageId,
    'ops': [
      for (final op in c.ops) [_kindTag(op.kind), op.id],
    ],
    'n': elements.length,
    if (c.modifiedAt != null) 'modifiedAt': c.modifiedAt!.toIso8601String(),
    if (c.header != null) 'header': jsonDecode(compactPageJson(_headerOf(c.header!))),
  };
  final head = utf8.encode(jsonEncode(header));
  final payload = elements.isEmpty
      ? Uint8List(0)
      : (() {
          final mini = PageData(
              pageId: c.pageId,
              pageNumber: 0,
              width: 0,
              height: 0,
              layers: RenderingLayers(content: elements));
          return binaryPageBytes(mini) ??
              Uint8List.fromList(utf8.encode(compactPageJson(mini)));
        })();
  final out = BytesBuilder(copy: false)
    ..add(_magic)
    ..addByte(_version)
    ..add(_varint(head.length))
    ..add(head)
    ..add(payload);
  return out.takeBytes();
}

/// Reads a chunk; [FormatException] when it is damaged, like a page.
OpChunk decodeChunk(List<int> bytes) {
  final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (b.length < 6 ||
      b[0] != _magic[0] ||
      b[1] != _magic[1] ||
      b[2] != _magic[2] ||
      b[3] != _magic[3]) {
    throw const FormatException('op chunk: bad magic');
  }
  if (b[4] > _version) throw ChunkTooNewException(b[4]);
  if (b[4] != _version) {
    throw const FormatException('op chunk: unknown version');
  }
  final (length, start) = _readVarint(b, 5);
  final end = start + length;
  if (end > b.length) throw const FormatException('op chunk: truncated');
  final Map<String, dynamic> h;
  try {
    h = jsonDecode(utf8.decode(Uint8List.sublistView(b, start, end)))
        as Map<String, dynamic>;
  } catch (_) {
    throw const FormatException('op chunk: bad header');
  }
  final pageId = h['pageId'];
  final rawOps = h['ops'];
  final n = h['n'];
  if (pageId is! String || rawOps is! List || n is! int) {
    throw const FormatException('op chunk: bad header');
  }
  final elements = end == b.length
      ? const <ContentElement>[]
      : decodePageBytes(Uint8List.sublistView(b, end)).layers.content;
  if (elements.length != n) {
    throw const FormatException('op chunk: element count');
  }
  var next = 0;
  final ops = <StrokeOp>[];
  for (final o in rawOps) {
    if (o is! List || o.length != 2 || o[1] is! String) {
      throw const FormatException('op chunk: bad op');
    }
    final kind = _kindOf(o[0]);
    final id = o[1] as String;
    if (kind == OpKind.delete) {
      ops.add(StrokeOp(kind, id));
      continue;
    }
    if (next >= elements.length || elements[next].id != id) {
      throw const FormatException('op chunk: ops and elements differ');
    }
    ops.add(StrokeOp(kind, id, elements[next++]));
  }
  if (next != elements.length) {
    throw const FormatException('op chunk: ops and elements differ');
  }
  final mod = h['modifiedAt'];
  final header = h['header'];
  return OpChunk(
    pageId: pageId,
    ops: ops,
    modifiedAt: mod is String ? DateTime.tryParse(mod) : null,
    header: header is Map<String, dynamic> ? decodePageData(header) : null,
  );
}

String _kindTag(OpKind k) => switch (k) {
      OpKind.add => 'a',
      OpKind.replace => 'r',
      OpKind.delete => 'd',
    };

OpKind _kindOf(Object? tag) => switch (tag) {
      'a' => OpKind.add,
      'r' => OpKind.replace,
      'd' => OpKind.delete,
      _ => throw const FormatException('op chunk: unknown op'),
    };

// Varints by arithmetic, not shifts: on the web an int is a double.
List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add(0x80 + v % 0x80);
    v = v ~/ 0x80;
  }
  out.add(v);
  return out;
}

(int, int) _readVarint(Uint8List b, int pos) {
  var v = 0, scale = 1;
  while (true) {
    if (pos >= b.length) throw const FormatException('truncated varint');
    final x = b[pos++];
    v += (x % 0x80) * scale;
    if (x < 0x80) return (v, pos);
    scale *= 0x80;
    if (scale > 9007199254740992) throw const FormatException('long varint');
  }
}

// ── Diff and apply ──

/// [page] without content and modifiedAt: what a header op carries.
PageData _headerOf(PageData page) => page.copyWith(
    layers: page.layers.copyWith(content: const []), modifiedAt: null);

/// The ops that turn [base] into [page], or null when they cannot say it
/// (another page, duplicate ids): write the page then.
OpChunk? diffPage(PageData base, PageData page) {
  if (base.pageId != page.pageId) return null;
  final baseById = <String, ContentElement>{};
  for (final e in base.layers.content) {
    if (baseById.containsKey(e.id)) return null;
    baseById[e.id] = e;
  }
  final pageIds = <String>{};
  for (final e in page.layers.content) {
    if (!pageIds.add(e.id)) return null;
  }
  final ops = <StrokeOp>[
    for (final id in baseById.keys)
      if (!pageIds.contains(id)) StrokeOp(OpKind.delete, id),
  ];
  for (final e in page.layers.content) {
    final b = baseById[e.id];
    if (b == null) {
      ops.add(StrokeOp(OpKind.add, e.id, e));
    } else if (!identical(b, e) && b != e) {
      ops.add(StrokeOp(OpKind.replace, e.id, e));
    }
  }
  final header = _headerOf(page);
  final chunk = OpChunk(
    pageId: page.pageId,
    ops: ops,
    modifiedAt: page.modifiedAt,
    header: header == _headerOf(base) ? null : header,
  );
  // The chunk must give back exactly this page's elements and fields. List
  // order is not kept: painting sorts by zIndex.
  return _sameContent(applyChunks(base, [chunk]), page) ? chunk : null;
}

bool _sameContent(PageData a, PageData b) {
  if (_headerOf(a) != _headerOf(b) || a.modifiedAt != b.modifiedAt) return false;
  final x = a.layers.content, y = b.layers.content;
  if (x.length != y.length) return false;
  final byId = {for (final e in x) e.id: e};
  if (byId.length != x.length) return false;
  for (final e in y) {
    final o = byId[e.id];
    if (o == null || (!identical(o, e) && o != e)) return false;
  }
  return true;
}

/// [snapshot] with [chunks] applied in the given order; chunks of another
/// page id are skipped.
PageData applyChunks(PageData snapshot, Iterable<OpChunk> chunks) {
  final slots = List<ContentElement?>.of(snapshot.layers.content);
  final at = <String, int>{};
  for (var i = 0; i < slots.length; i++) {
    at.putIfAbsent(slots[i]!.id, () => i); // a duplicate stays as it is
  }
  PageData? header;
  var modifiedAt = snapshot.modifiedAt;
  var touched = false;
  for (final c in chunks) {
    if (c.pageId != snapshot.pageId) continue;
    touched = true;
    if (c.header != null) header = c.header;
    if (c.modifiedAt != null) modifiedAt = c.modifiedAt;
    for (final op in c.ops) {
      final i = at[op.id];
      switch (op.kind) {
        case OpKind.add:
          if (i == null) {
            at[op.id] = slots.length;
            slots.add(op.element);
          }
        case OpKind.replace:
          if (i != null) slots[i] = op.element;
        case OpKind.delete:
          if (i != null) {
            slots[i] = null;
            at.remove(op.id);
          }
      }
    }
  }
  if (!touched) return snapshot;
  final base = header ?? snapshot;
  return base.copyWith(
    pageId: snapshot.pageId,
    layers: base.layers
        .copyWith(content: [for (final e in slots) if (e != null) e]),
    modifiedAt: modifiedAt,
  );
}

// ── Folded chunks in a snapshot ──

const _foldedKey = '{"foldedOps":[';

/// [pageBytes] with `"foldedOps"` as the first key of its JSON: the chunks
/// this snapshot already contains. Old releases ignore the key.
Uint8List withFoldedOps(Uint8List pageBytes, Iterable<ChunkId> folded) {
  final ids = folded.map((c) => c.id).toList()..sort();
  if (ids.isEmpty) return pageBytes;
  final prefix = utf8.encode('$_foldedKey${ids.map(jsonEncode).join(',')}],');
  if (!isBinaryPage(pageBytes)) {
    if (pageBytes.length < 3 || pageBytes[0] != 0x7B) return pageBytes;
    return Uint8List.fromList(
        [...prefix, ...Uint8List.sublistView(pageBytes, 1)]);
  }
  final (length, start) = _readVarint(pageBytes, 5);
  if (length < 3 || pageBytes[start] != 0x7B) return pageBytes;
  final json = Uint8List.sublistView(pageBytes, start + 1, start + length);
  final out = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(pageBytes, 0, 5))
    ..add(_varint(prefix.length + json.length))
    ..add(prefix)
    ..add(json)
    ..add(Uint8List.sublistView(pageBytes, start + length));
  return out.takeBytes();
}

/// The chunks a snapshot says it folded; empty for any other page.
Set<ChunkId> foldedOpsOf(Uint8List pageBytes) {
  var start = 0;
  if (isBinaryPage(pageBytes)) {
    if (pageBytes.length < 6) return const {};
    start = _readVarint(pageBytes, 5).$2;
  }
  final key = utf8.encode(_foldedKey);
  if (pageBytes.length < start + key.length) return const {};
  for (var i = 0; i < key.length; i++) {
    if (pageBytes[start + i] != key[i]) return const {};
  }
  final open = start + key.length - 1;
  final close = pageBytes.indexOf(0x5D, open); // ']'
  if (close < 0) return const {};
  try {
    final list =
        jsonDecode(utf8.decode(Uint8List.sublistView(pageBytes, open, close + 1)))
            as List;
    return {
      for (final s in list)
        if (s is String)
          if (ChunkId.parse(s) case final id?) id,
    };
  } catch (_) {
    return const {};
  }
}
