import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/symbol_library_service.dart';
import 'package:abelnotes/features/canvas/data/element_geometry.dart';

/// Reusable symbols & libraries. The library is device-wide (FileService.
/// globalSymbolsPath); `state.symbolLibraries` is its in-memory view, and each
/// notebook's own symbols.json is merged into it on open.
class SymbolsLibrary {
  SymbolsLibrary(this._core);

  final CanvasCore _core;

  CanvasState? get state => _core.state;
  set state(CanvasState? v) => _core.state = v;

  /// Ids the user has deleted, mirrored from the shared library so the
  /// mutators below can add to them. The service owns the durable copy.
  Set<String> _deletedSymbolIds = {};
  Set<String> _deletedLibraryIds = {};

  SymbolLibraryService get _symbols =>
      _core.ref.read(symbolLibraryServiceProvider);

  /// Folds the notebook's own symbols into the device-wide library on open
  /// and adopts its tombstones. A preview stays out of it (null).
  Future<SymbolCollection?> mergeOnOpen(
      List<SymbolLibrary>? symbolLibraries, {required bool preview}) async {
    final merged = preview
        ? null
        : await _symbols.merge(
            SymbolCollection(libraries: symbolLibraries ?? const []),
          );
    _deletedSymbolIds = {...?merged?.deletedSymbolIds};
    _deletedLibraryIds = {...?merged?.deletedLibraryIds};
    return merged;
  }

  /// Catch up with the other devices in the background.
  void reconcileInBackground() => unawaited(_symbols.reconcile());

  /// The live libraries plus the tombstones, as one value to hand the service.
  SymbolCollection _symbolCollection() => SymbolCollection(
        libraries: state?.symbolLibraries ?? const [],
        deletedSymbolIds: _deletedSymbolIds,
        deletedLibraryIds: _deletedLibraryIds,
      );

  /// Persist a symbol change to the shared library and let the other devices
  /// know. Fire-and-forget: both the write and the upload are safe to lose.
  void _publish() {
    final collection = _symbolCollection();
    unawaited(() async {
      await _symbols.save(collection);
      await _symbols.reconcile();
    }());
  }

  /// Returns the first library, or creates a default one if none exists.
  SymbolLibrary _defaultLibrary(String name) {
    if (state!.symbolLibraries.isEmpty) {
      final lib = SymbolLibrary(id: const Uuid().v4(), name: name);
      state = state!.copyWith(symbolLibraries: [lib], isDirty: true);
      _publish();
      return lib;
    }
    return state!.symbolLibraries.first;
  }

  void createSymbolLibrary(String name) {
    if (state == null) return;
    final lib = SymbolLibrary(id: const Uuid().v4(), name: name);
    state = state!.copyWith(
        symbolLibraries: [...state!.symbolLibraries, lib], isDirty: true);
    _publish();
  }

  void renameSymbolLibrary(String libId, String newName) {
    if (state == null) return;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) => l.id == libId ? l.copyWith(name: newName) : l).toList(),
      isDirty: true,
    );
    _publish();
  }

  void deleteSymbolLibrary(String libId) {
    if (state == null) return;
    // Tombstone the symbols too, not just the library: another notebook may
    // carry them under a library id that survives, and the merge on open
    // would put them back.
    for (final l in state!.symbolLibraries.where((l) => l.id == libId)) {
      _deletedSymbolIds.addAll(l.symbols.map((sym) => sym.id));
    }
    _deletedLibraryIds.add(libId);
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.where((l) => l.id != libId).toList(),
      isDirty: true,
    );
    _publish();
  }

  void renameSymbol(String libId, String symbolId, String newName) {
    if (state == null) return;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != libId) return l;
        return l.copyWith(symbols: l.symbols.map((s) => s.id == symbolId
            ? ReusableSymbol(id: s.id, name: newName, elements: s.elements, bounds: s.bounds, createdAt: s.createdAt)
            : s).toList());
      }).toList(),
      isDirty: true,
    );
    _publish();
  }

  void deleteSymbolFromLibrary(String libId, String symbolId) {
    if (state == null) return;
    _deletedSymbolIds.add(symbolId);
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != libId) return l;
        return l.copyWith(symbols: l.symbols.where((s) => s.id != symbolId).toList());
      }).toList(),
      isDirty: true,
    );
    _publish();
  }

  /// Creates a symbol from the current lasso selection and adds it to the
  /// target library (first library if [targetLibId] is null).
  void createSymbolFromSelection(String name,
      {String? targetLibId, required String defaultLibraryName}) {
    if (state == null || state!.lassoSelection == null) return;
    final sel = state!.lassoSelection!;
    final page = state!.currentPage;
    if (page == null) return;

    final elements = page.layers.content.where((element) {
      final id = element.id;
      return sel.selectedIds.contains(id);
    }).toList();

    if (elements.isEmpty) return;

    final symbol = ReusableSymbol(
      id: const Uuid().v4(),
      name: name,
      elements: elements,
      bounds: sel.bounds,
      createdAt: DateTime.now(),
    );

    // Ensure there is at least one library
    _defaultLibrary(defaultLibraryName);

    final targetId = targetLibId ?? state!.symbolLibraries.first.id;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != targetId) return l;
        return l.copyWith(symbols: [...l.symbols, symbol]);
      }).toList(),
      isDirty: true,
    );
    _publish();
  }

  void createSymbolFromElement(String elementId, String name,
      {required String defaultLibraryName}) {
    if (state == null) return;
    final page = state!.currentPage;
    if (page == null) return;

    final element = page.layers.content.where((e) {
      final id = e.id;
      return id == elementId;
    }).firstOrNull;
    if (element == null) return;

    final bounds = getElementBounds(element);
    if (bounds == null) return;

    final symbol = ReusableSymbol(
      id: const Uuid().v4(),
      name: name,
      elements: [element],
      bounds: bounds,
      createdAt: DateTime.now(),
    );

    _defaultLibrary(defaultLibraryName);
    final targetId = state!.symbolLibraries.first.id;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != targetId) return l;
        return l.copyWith(symbols: [...l.symbols, symbol]);
      }).toList(),
      isDirty: true,
    );
    _publish();
  }

  void clearPendingSymbol() {
    if (state == null) return;
    state = state!.copyWith(clearPendingSymbol: true);
  }
}
