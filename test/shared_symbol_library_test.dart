// The symbol library is device-wide, but every notebook keeps its own copy of
// the symbols it has seen (that copy is what syncs to the server and travels
// inside an exported .abelnote). Merging the two on open is what makes the
// library shared — and what could silently resurrect a deleted symbol, since
// every older notebook still carries it. Data-critical, so the resurrection
// cases are pinned here.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/symbol_library_service.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';

ReusableSymbol _sym(String id) => ReusableSymbol(
      id: id,
      name: id,
      elements: const [],
      bounds: const Rect.fromLTWH(0, 0, 10, 10),
      createdAt: DateTime(2026),
    );

SymbolLibrary _lib(String id, List<String> symbolIds) =>
    SymbolLibrary(id: id, name: id, symbols: symbolIds.map(_sym).toList());

List<String> _ids(List<SymbolLibrary> libs) =>
    [for (final l in libs) for (final s in l.symbols) s.id]..sort();

List<SymbolLibrary> _merge(
  List<SymbolLibrary> shared,
  List<SymbolLibrary> notebook, {
  Set<String> deletedSymbols = const {},
  Set<String> deletedLibraries = const {},
}) =>
    mergeSymbolLibraries(shared, notebook,
        deletedSymbolIds: deletedSymbols.toSet(),
        deletedLibraryIds: deletedLibraries.toSet());

void main() {
  test('a notebook opened for the first time contributes its symbols', () {
    // The migration case: symbols that existed before the library was shared.
    final merged = _merge(const [], [_lib('L', ['a', 'b'])]);
    expect(_ids(merged), ['a', 'b']);
  });

  test('symbols saved in another notebook are visible in this one', () {
    final merged = _merge([_lib('L', ['a'])], [_lib('L', ['b'])]);
    expect(_ids(merged), ['a', 'b']);
  });

  test('a symbol present on both sides is not duplicated', () {
    final merged = _merge([_lib('L', ['a'])], [_lib('L', ['a'])]);
    expect(_ids(merged), ['a']);
  });

  test('a deleted symbol is not resurrected by an older notebook', () {
    final merged = _merge(
      [_lib('L', ['a'])],
      [_lib('L', ['a', 'gone'])],
      deletedSymbols: {'gone'},
    );
    expect(_ids(merged), ['a']);
  });

  test('a deleted library is not resurrected, symbols included', () {
    final merged = _merge(
      const [],
      [_lib('L', ['a']), _lib('KEEP', ['b'])],
      deletedLibraries: {'L'},
      deletedSymbols: {'a'},
    );
    expect(merged.map((l) => l.id), ['KEEP']);
    expect(_ids(merged), ['b']);
  });

  test('a library emptied by deletions does not come back as an empty shell',
      () {
    final merged = _merge(
      const [],
      [_lib('L', ['gone'])],
      deletedSymbols: {'gone'},
    );
    expect(merged, isEmpty);
  });

  test('a genuinely empty new library is still carried over', () {
    final merged = _merge(const [], [_lib('EMPTY', const [])]);
    expect(merged.map((l) => l.id), ['EMPTY']);
  });

  test('the shared side wins on name, and its order is preserved', () {
    final merged = _merge(
      [_lib('B', ['b']), _lib('A', ['a'])],
      [SymbolLibrary(id: 'B', name: 'renamed-in-notebook', symbols: [_sym('c')])],
    );
    expect(merged.map((l) => l.id), ['B', 'A']);
    expect(merged.first.name, 'B');
    expect(_ids(merged), ['a', 'b', 'c']);
  });

  // ── Cross-device reconcile ──
  //
  // The remote file and the local one are merged with the same union. These
  // pin the properties that make it safe to do that with no conflict UI:
  // order-independence, and that a deletion made on one device sticks when
  // the other still has the symbol.

  group('two devices', () {
    SymbolCollection collection(
      List<SymbolLibrary> libs, {
      Set<String> deletedSymbols = const {},
    }) =>
        SymbolCollection(libraries: libs, deletedSymbolIds: deletedSymbols);

    test('merging is commutative — either side may reconcile first', () {
      final a = collection([_lib('L', ['a'])]);
      final b = collection([_lib('L', ['b'])]);
      expect(_ids(a.mergedWith(b).libraries), ['a', 'b']);
      expect(_ids(b.mergedWith(a).libraries), ['a', 'b']);
    });

    test('merging is idempotent — reconciling twice changes nothing', () {
      final a = collection([_lib('L', ['a'])]);
      final b = collection([_lib('L', ['b'])]);
      final once = a.mergedWith(b);
      final twice = once.mergedWith(b);
      expect(_ids(twice.libraries), _ids(once.libraries));
      expect(once.sameAs(twice), isTrue);
    });

    test('a deletion on one device wins over a device that still has it', () {
      final deleter = collection(const [], deletedSymbols: {'a'});
      final stale = collection([_lib('L', ['a'])]);
      // Whichever way round the reconcile happens, the symbol stays gone.
      expect(_ids(deleter.mergedWith(stale).libraries), isEmpty);
      expect(_ids(stale.mergedWith(deleter).libraries), isEmpty);
    });

    test('tombstones travel, so the stale device stops re-uploading it', () {
      final merged =
          collection([_lib('L', ['a'])]).mergedWith(
              collection(const [], deletedSymbols: {'a'}));
      expect(merged.deletedSymbolIds, contains('a'));
    });

    test('survives a round trip through JSON', () {
      final original = SymbolCollection(
        libraries: [_lib('L', ['a', 'b'])],
        deletedSymbolIds: const {'x'},
        deletedLibraryIds: const {'y'},
      );
      final restored = SymbolCollection.decode(original.encode());
      expect(_ids(restored.libraries), ['a', 'b']);
      expect(restored.deletedSymbolIds, {'x'});
      expect(restored.deletedLibraryIds, {'y'});
      expect(restored.sameAs(original), isTrue);
    });

    test('a corrupt file degrades to empty instead of throwing', () {
      expect(SymbolCollection.decode(Uint8List.fromList([1, 2, 3])).isEmpty,
          isTrue);
    });
  });
}
