// Pages only this device lists (added offline, or kept against a remote
// delete) used to be appended to the notebook; they belong where they were.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

PageEntry _p(String f) =>
    PageEntry(pageId: 'id-$f', pageNumber: 0, fileName: f);
List<String> _names(List<PageEntry> l) => [for (final e in l) e.fileName];

void main() {
  test('a page kept against a remote delete returns to its slot', () {
    final out = CanvasNotifier.placeByLocalOrder(
      [_p('1'), _p('3'), _p('4')],
      [_p('2')],
      [_p('1'), _p('2'), _p('3'), _p('4')],
    );
    expect(_names(out), ['1', '2', '3', '4']);
  });

  test('follows the remote order around it', () {
    // Remote moved 4 first; local inserted 5 after 2.
    final out = CanvasNotifier.placeByLocalOrder(
      [_p('4'), _p('1'), _p('2'), _p('3')],
      [_p('5')],
      [_p('1'), _p('2'), _p('5'), _p('3'), _p('4')],
    );
    expect(_names(out), ['4', '1', '2', '5', '3']);
  });

  test('a page that was first locally stays first', () {
    final out = CanvasNotifier.placeByLocalOrder(
      [_p('2'), _p('3')],
      [_p('1')],
      [_p('1'), _p('2'), _p('3')],
    );
    expect(_names(out), ['1', '2', '3']);
  });

  test('consecutive extras keep their local order', () {
    final out = CanvasNotifier.placeByLocalOrder(
      [_p('1'), _p('4')],
      [_p('3'), _p('2')],
      [_p('1'), _p('2'), _p('3'), _p('4')],
    );
    expect(_names(out), ['1', '2', '3', '4']);
  });
}
