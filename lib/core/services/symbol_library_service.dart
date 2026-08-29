import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/remote_store.dart';

/// The whole symbol library as one value: the libraries themselves plus the
/// ids of everything the user has deleted.
///
/// The tombstones are not bookkeeping, they are what makes the library
/// mergeable. Every notebook keeps its own copy of the symbols it has seen,
/// and so does every device — so without a record of what was deleted, any
/// stale copy would silently put a deleted symbol back the next time it was
/// merged, and there would be no way to ever get rid of one.
///
/// Together the two sets form a two-phase set: merging is a plain union on
/// both halves, which is commutative, associative and idempotent. That is why
/// syncing this across devices needs no conflict resolution at all — unlike
/// pages, two devices editing the library concurrently converge on their own,
/// whatever order the merges happen in.
@immutable
class SymbolCollection {
  static const int formatVersion = 1;

  final List<SymbolLibrary> libraries;
  final Set<String> deletedSymbolIds;
  final Set<String> deletedLibraryIds;

  const SymbolCollection({
    this.libraries = const [],
    this.deletedSymbolIds = const {},
    this.deletedLibraryIds = const {},
  });

  static const empty = SymbolCollection();

  bool get isEmpty =>
      libraries.isEmpty && deletedSymbolIds.isEmpty && deletedLibraryIds.isEmpty;

  int get symbolCount =>
      libraries.fold(0, (n, l) => n + l.symbols.length);

  Map<String, dynamic> toJson() => {
        'version': formatVersion,
        'libraries': libraries.map((l) => l.toJson()).toList(),
        // Sorted so an unchanged collection serialises byte-identically and
        // [sameAs] below can stay a cheap structural compare.
        'deletedSymbols': deletedSymbolIds.toList()..sort(),
        'deletedLibraries': deletedLibraryIds.toList()..sort(),
      };

  /// Never throws on malformed input: a corrupt or truncated file must not
  /// stop a notebook from opening. The worst case is an empty collection,
  /// which the next merge repopulates from whatever the notebooks carry.
  factory SymbolCollection.fromJson(Object? decoded) {
    if (decoded is! Map) return empty;
    final libs = <SymbolLibrary>[];
    for (final raw in (decoded['libraries'] as List? ?? const [])) {
      try {
        libs.add(SymbolLibrary.fromJson(Map<String, dynamic>.from(raw as Map)));
      } catch (e) {
        // Drop the one unreadable library, keep the rest.
        debugPrint('[Symbols] skipping unreadable library: $e');
      }
    }
    return SymbolCollection(
      libraries: libs,
      deletedSymbolIds: {
        for (final e in (decoded['deletedSymbols'] as List? ?? const []))
          e.toString()
      },
      deletedLibraryIds: {
        for (final e in (decoded['deletedLibraries'] as List? ?? const []))
          e.toString()
      },
    );
  }

  static SymbolCollection decode(Uint8List bytes) {
    try {
      return SymbolCollection.fromJson(jsonDecode(utf8.decode(bytes)));
    } catch (e) {
      debugPrint('[Symbols] collection unreadable: $e');
      return empty;
    }
  }

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Union with [other], keeping THIS side's library names and ordering.
  ///
  /// Membership converges regardless of which side is which — that is the
  /// property that matters. A library *name* changed on two devices at once
  /// settles to whichever side merged last; one more rename fixes it, and
  /// there is no timestamp in the format to do better without a version bump.
  SymbolCollection mergedWith(SymbolCollection other) {
    final deletedSymbols = {...deletedSymbolIds, ...other.deletedSymbolIds};
    final deletedLibraries = {...deletedLibraryIds, ...other.deletedLibraryIds};
    return SymbolCollection(
      libraries: mergeSymbolLibraries(
        libraries,
        other.libraries,
        deletedSymbolIds: deletedSymbols,
        deletedLibraryIds: deletedLibraries,
      ),
      deletedSymbolIds: deletedSymbols,
      deletedLibraryIds: deletedLibraries,
    );
  }

  /// Cheap "is this the same collection?" used to skip pointless disk writes
  /// and uploads. Compares identity of the members, not their contents — a
  /// symbol's strokes never change once saved, only the set of symbols does.
  bool sameAs(SymbolCollection other) {
    if (libraries.length != other.libraries.length) return false;
    if (deletedSymbolIds.length != other.deletedSymbolIds.length) return false;
    if (deletedLibraryIds.length != other.deletedLibraryIds.length) return false;
    for (var i = 0; i < libraries.length; i++) {
      final a = libraries[i];
      final b = other.libraries[i];
      if (a.id != b.id || a.name != b.name) return false;
      if (a.symbols.length != b.symbols.length) return false;
      for (var j = 0; j < a.symbols.length; j++) {
        if (a.symbols[j].id != b.symbols[j].id) return false;
        if (a.symbols[j].name != b.symbols[j].name) return false;
      }
    }
    return deletedSymbolIds.containsAll(other.deletedSymbolIds) &&
        deletedLibraryIds.containsAll(other.deletedLibraryIds);
  }
}

/// Union of two lists of libraries, skipping anything tombstoned.
/// [mine] wins on name and ordering; [theirs] contributes what is missing.
List<SymbolLibrary> mergeSymbolLibraries(
  List<SymbolLibrary> mine,
  List<SymbolLibrary> theirs, {
  required Set<String> deletedSymbolIds,
  required Set<String> deletedLibraryIds,
}) {
  final merged = <SymbolLibrary>[
    for (final l in mine)
      if (!deletedLibraryIds.contains(l.id))
        // A tombstoned symbol can still be sitting in our own list if the
        // deletion arrived from another device with this very merge.
        l.copyWith(
          symbols: l.symbols
              .where((sym) => !deletedSymbolIds.contains(sym.id))
              .toList(),
        ),
  ];
  for (final incoming in theirs) {
    if (deletedLibraryIds.contains(incoming.id)) continue;
    final keep = incoming.symbols
        .where((sym) => !deletedSymbolIds.contains(sym.id))
        .toList();
    final idx = merged.indexWhere((l) => l.id == incoming.id);
    if (idx < 0) {
      // A library whose every symbol was deleted must not come back as an
      // empty shell; one that was always empty is a real (new) library.
      if (keep.isEmpty && incoming.symbols.isNotEmpty) continue;
      merged.add(incoming.copyWith(symbols: keep));
      continue;
    }
    final existing = merged[idx];
    final known = existing.symbols.map((sym) => sym.id).toSet();
    final added = keep.where((sym) => !known.contains(sym.id)).toList();
    if (added.isEmpty) continue;
    merged[idx] = existing.copyWith(symbols: [...existing.symbols, ...added]);
  }
  return merged;
}

/// Owns the device-wide symbol library: one file on disk, one file on the
/// remote, and the merge that keeps them agreeing.
///
/// Deliberately independent of any open notebook. The library belongs to the
/// user, not to a notebook — it has to be readable and syncable with nothing
/// open, which is also why it does not live in `CanvasNotifier`.
class SymbolLibraryService {
  SymbolLibraryService({
    required FileService fileService,
    required RemoteStore? Function() remoteStore,
  })  : _files = fileService,
        _remoteStore = remoteStore;

  final FileService _files;
  final RemoteStore? Function() _remoteStore;

  /// File name at the remote root. Sits next to the notebooks rather than
  /// inside one, because it belongs to none of them.
  static const String remoteFileName = 'symbols.json';

  SymbolCollection? _cache;

  /// Version token of the remote file as of the last successful reconcile.
  /// Lets the common case — nothing changed anywhere — cost one HEAD-sized
  /// round trip instead of downloading the whole library.
  String? _lastRemoteVersion;

  /// Serialises reconciles so a timer tick and a user edit can't interleave
  /// their read-merge-write cycles and lose one side's additions.
  Future<void>? _inFlight;

  /// The library as it is on this device.
  Future<SymbolCollection> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final bytes = await _files.readGlobalSymbols();
    final loaded = bytes == null ? SymbolCollection.empty : SymbolCollection.decode(bytes);
    _cache = loaded;
    return loaded;
  }

  /// What [load] last returned, without touching the disk. Null before the
  /// first load.
  SymbolCollection? get cached => _cache;

  /// Replaces the stored library. Skips the write when nothing changed, so
  /// merges that find no news don't churn the disk.
  Future<void> save(SymbolCollection collection) async {
    final previous = _cache;
    if (previous != null && previous.sameAs(collection)) return;
    _cache = collection;
    try {
      await _files.writeGlobalSymbols(collection.encode());
    } catch (e) {
      // A failed write means a stale library next launch, not lost work: the
      // in-memory copy stays authoritative for this session and the next
      // save or reconcile rewrites it.
      debugPrint('[Symbols] local write failed: $e');
    }
  }

  /// Folds [incoming] into the stored library and returns the result.
  /// Used both for what a notebook carries and for what the remote holds.
  Future<SymbolCollection> merge(SymbolCollection incoming) async {
    if (incoming.isEmpty) return load();
    final merged = (await load()).mergedWith(incoming);
    await save(merged);
    return merged;
  }

  String? _remotePath(RemoteStore store) {
    final base = store.basePath;
    if (base.isEmpty) return null;
    return base.endsWith('/')
        ? '$base$remoteFileName'
        : '$base/$remoteFileName';
  }

  /// Brings the local and remote libraries into agreement.
  ///
  /// Pull, merge, push-if-we-added-anything. Because the merge is a union of
  /// two-phase sets there is no conflict to resolve and no ordering to get
  /// right: if two devices push at once one upload wins, and the loser still
  /// holds its own additions locally and re-pushes them on its next
  /// reconcile. Both sides converge.
  ///
  /// Never throws — offline is the normal state for an offline-first app, and
  /// the local library is already the source of truth.
  Future<void> reconcile() {
    final running = _inFlight;
    if (running != null) return running;
    final started = _reconcile().whenComplete(() => _inFlight = null);
    _inFlight = started;
    return started;
  }

  Future<void> _reconcile() async {
    final store = _remoteStore();
    if (store == null) return; // local-only, or no backend configured yet
    final path = _remotePath(store);
    if (path == null) return;

    final local = await load();

    try {
      final version = await store.getVersion(path);

      if (version != null && version == _lastRemoteVersion) {
        // Remote is what we last merged. Only work left is pushing anything
        // we've added since.
        await _pushIfNeeded(store, path, local, SymbolCollection.empty);
        return;
      }

      SymbolCollection remote = SymbolCollection.empty;
      if (version != null) {
        // criticalVerify: a short read here would look like "symbols were
        // deleted upstream" and the merge would keep the truncated set.
        final bytes = await store.downloadFile(path, criticalVerify: true);
        remote = SymbolCollection.decode(bytes);
      }

      final merged = local.mergedWith(remote);
      await save(merged);
      _lastRemoteVersion = version;
      await _pushIfNeeded(store, path, merged, remote);
    } catch (e) {
      debugPrint('[Symbols] reconcile skipped: $e');
    }
  }

  /// Uploads only when the merged result says something the remote doesn't.
  Future<void> _pushIfNeeded(
    RemoteStore store,
    String path,
    SymbolCollection merged,
    SymbolCollection remote,
  ) async {
    if (merged.isEmpty) return;
    if (remote.sameAs(merged)) return;
    await store.ensureBaseDirectory();
    // skipVerify: the file is small and re-uploaded on the next reconcile if
    // it didn't land, so a read-back on every push isn't worth the round trip.
    _lastRemoteVersion =
        await store.uploadFile(path, merged.encode(), skipVerify: true);
  }

  /// Drops the cached remote version so the next reconcile re-reads the file.
  /// Called when the backend changes underneath us — the new remote's library
  /// has nothing to do with the old one's version token.
  void forgetRemoteVersion() => _lastRemoteVersion = null;
}
