// Samsung Notes (.sdocx) pages are rebuilt from a synthetic archive: strokes
// land scaled on A4, keep colour and width, and a stroke drawn past the
// bottom of its page continues on the next one.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/samsung_notes_importer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

class _W {
  final b = BytesBuilder();
  final _d = ByteData(8);
  void u8(int v) => b.addByte(v);
  void u16(int v) => _put(2, () => _d.setUint16(0, v, Endian.little));
  void u32(int v) => _put(4, () => _d.setUint32(0, v, Endian.little));
  void i32(int v) => _put(4, () => _d.setInt32(0, v, Endian.little));
  void i64(int v) => _put(8, () => _d.setInt64(0, v, Endian.little));
  void f32(double v) => _put(4, () => _d.setFloat32(0, v, Endian.little));
  void f64(double v) => _put(8, () => _d.setFloat64(0, v, Endian.little));
  void bytes(List<int> v) => b.add(v);
  void mask(int v) {
    u8(4);
    u32(v);
  }

  void utf16(String s) {
    u16(s.length);
    for (final c in s.codeUnits) {
      u16(c);
    }
  }

  void _put(int n, void Function() f) {
    f();
    b.add(_d.buffer.asUint8List(0, n));
  }

  Uint8List done() => b.takeBytes();
}

/// Frame: total, kind, header size, masks, fixed, flexible.
Uint8List _frame(int kind, int props, int fields, Uint8List fixed,
    [Uint8List? flex]) {
  final w = _W();
  final header = 4 + 2 + 4 + 5 + 5 + fixed.length;
  w.u32(header + (flex?.length ?? 0));
  w.u16(kind);
  w.u32(header);
  w.mask(props);
  w.mask(fields);
  w.bytes(fixed);
  if (flex != null) w.bytes(flex);
  return w.done();
}

/// One stroke object (type 1), compressed points in 1/32 px steps.
Uint8List _stroke(List<(double, double)> pts, {required int color,
    required double size}) {
  final base = _W()
    ..u32(5400)
    ..u16(0)
    ..i64(0)
    ..f64(0)
    ..f64(0)
    ..f64(0)
    ..f64(0)
    ..i32(0)
    ..u8(0);
  final fixed = _W()
    ..u16(pts.length)
    ..f64(pts.first.$1)
    ..f64(pts.first.$2);
  int enc(double d) =>
      d < 0 ? 0x8000 | (-d * 32).round() : (d * 32).round();
  for (var i = 1; i < pts.length; i++) {
    fixed
      ..u16(enc(pts[i].$1 - pts[i - 1].$1))
      ..u16(enc(pts[i].$2 - pts[i - 1].$2));
  }
  fixed.f32(1);
  for (var i = 1; i < pts.length; i++) {
    fixed.u16(0);
  }
  fixed.i32(0);
  for (var i = 1; i < pts.length; i++) {
    fixed.u16(0);
  }
  fixed.u16(1);
  final flex = _W()
    ..u32(color)
    ..f32(size);
  final payload = _W()
    ..bytes(_frame(0, 1 << 3, 0, base.done()))
    ..bytes(_frame(1, 1, (1 << 2) | (1 << 3), fixed.done(), flex.done()));
  final p = payload.done();
  return (_W()
        ..u8(1)
        ..u16(0)
        ..u32(p.length + 32)
        ..bytes(p)
        ..bytes(List.filled(32, 0)))
      .done();
}

Uint8List _page(String id, List<Uint8List> objects) {
  final head = _W()
    ..u32(0) // layer offset, patched below
    ..u32(0)
    ..mask(0)
    ..mask(0)
    ..u32(0)
    ..u32(1080)
    ..u32(1527)
    ..u32(0)
    ..u32(0)
    ..utf16(id);
  final h = head.done();
  ByteData.sublistView(h).setUint32(0, h.length, Endian.little);
  final w = _W()
    ..bytes(h)
    ..u16(1)
    ..u16(0)
    ..u32(14)
    ..bytes(List.filled(10, 0))
    ..u32(objects.length);
  for (final o in objects) {
    w.bytes(o);
  }
  w.bytes(List.filled(32, 0));
  return w.done();
}

ArchiveFile _file(String name, Uint8List b) => ArchiveFile(name, b.length, b);

Uint8List _sdocx(Map<String, Uint8List> pages, List<String> order) {
  final info = _W()
    ..bytes(List.filled(32, 0))
    ..u16(order.length);
  for (final id in order) {
    info
      ..utf16(id)
      ..bytes(List.filled(32, 0));
  }
  final a = Archive()
    ..addFile(_file('pageIdInfo.dat', info.done()));
  pages.forEach((id, b) => a.addFile(_file('$id.page', b)));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

List<StrokeData> _strokes(List<ContentElement> els) =>
    [for (final e in els) if (e is StrokeElement) e.data];

void main() {
  const s = 595 / 1080;

  test('strokes land on A4 pages in pageIdInfo order', () {
    final bytes = _sdocx({
      'b': _page('b', [
        _stroke([(100, 100), (200, 150), (300, 100)],
            color: 0xFF335FFF, size: 8),
      ]),
      'a': _page('a', [
        _stroke([(540, 700), (560, 720)], color: 0xFF000000, size: 4),
      ]),
    }, [
      'a',
      'b'
    ]);
    final parsed = SamsungNotesImporter().parse(bytes, fallbackTitle: 'Note');
    expect(parsed.title, 'Note');
    expect(parsed.pageWidth, 595);
    expect(parsed.pageHeight, closeTo(1527 * s, 0.01));
    final pages = parsed.chapters.single.pages;
    expect(pages, hasLength(2));
    final first = _strokes(pages[0].elements).single;
    expect(first.points.first.x, closeTo(540 * s, 0.01));
    final second = _strokes(pages[1].elements).single;
    expect(second.color, 0xFF335FFF);
    expect(second.baseWidth, closeTo(8 * s, 0.01));
    expect([for (final p in second.points) p.y / s],
        [closeTo(100, 0.05), closeTo(150, 0.05), closeTo(100, 0.05)]);
    expect(parsed.issues, isEmpty);
  });

  test('a stroke past the page bottom continues on the next page', () {
    final bytes = _sdocx({
      'a': _page('a', [
        _stroke([(500, 1400), (500, 1500), (500, 1600), (500, 1700)],
            color: 0xFF000000, size: 4),
      ]),
    }, [
      'a'
    ]);
    final pages =
        SamsungNotesImporter().parse(bytes, fallbackTitle: 'N').chapters.single.pages;
    expect(pages, hasLength(2), reason: 'a page is added for the overflow');
    final top = _strokes(pages[0].elements).single;
    final bottom = _strokes(pages[1].elements).single;
    expect(top.points.last.y / s, greaterThan(1527));
    // Page stride = height + 24 px gap.
    expect(bottom.points.last.y / s, closeTo(1700 - 1551, 0.05));
  });

  test('not an archive is a readable error', () {
    expect(
        () => SamsungNotesImporter()
            .parse(Uint8List.fromList(utf8.encode('nope')), fallbackTitle: 'x'),
        throwsA(isA<ImportException>()));
  });
}
