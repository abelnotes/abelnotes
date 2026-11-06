import 'dart:async' show TimeoutException;
import 'package:abelnotes/core/platform/io.dart' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:abelnotes/ui/primitives/hw_open_route.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_screen.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

/// Thrown when the notebook has no local copy and no server is reachable
/// to download it. Typed (instead of a bare `Exception(message)`) so the
/// catch below can show a localized message to the user.
class NoLocalCopyOfflineException implements Exception {
  @override
  String toString() =>
      'NoLocalCopyOfflineException: no local copy and not connected to a server';
}

/// True while an open is between "loader shown" and "CanvasScreen pushed".
///
/// Opening is slow enough to be tapped twice (loading + parsing, and on a
/// fresh notebook the create that precedes it), and every extra tap used to
/// push its own CanvasScreen. Two editors on the stack is how the user got
/// trapped: back popped the top one, `closeNotebook()` nulled the shared
/// canvasProvider, and the second editor underneath rebuilt into the
/// "no notebook open" fallback with nothing left to open.
///
/// Cancel releases it at once (the stale call may sit minutes in a download),
/// and a generation token keeps that stale call from touching the canvas or
/// navigator when it finally resumes.
@visibleForTesting
class OpenGate {
  int _gen = 0;
  bool _busy = false;

  /// A token for the new open, or null when one is already in flight.
  int? begin() {
    if (_busy) return null;
    _busy = true;
    return ++_gen;
  }

  /// True while [token] is the open the user is still waiting for.
  bool isCurrent(int token) => _busy && token == _gen;

  /// Releases the guard and invalidates [token].
  void cancel(int token) {
    if (token != _gen) return;
    _busy = false;
    _gen++;
  }

  /// True when [token] was cancelled and no newer open started since.
  bool cancelledWithoutSuccessor(int token) => !_busy && _gen == token + 1;

  void end(int token) {
    if (token == _gen) _busy = false;
  }
}

final _openGate = OpenGate();

/// Opens a notebook: loads it (local first, server fallback), populates
/// canvasProvider, then pushes the editor screen. Mirrors the legacy
/// flow so the new UI inherits all the corruption-recovery logic.
/// With [origin] (the tapped cover, global coords) the editor grows out of
/// it and closes back into it.
Future<void> openNotebookAndNavigate(
  BuildContext context,
  WidgetRef ref,
  NotebookEntry entry, {
  Rect? origin,
}) async {
  final token = _openGate.begin();
  if (token == null) return;
  try {
    await _openNotebookAndNavigate(context, ref, entry, origin, token);
  } finally {
    _openGate.end(token);
  }
}

Route<void> _editorRoute(Rect? origin, NotebookEntry entry) => origin == null
    ? MaterialPageRoute(builder: (_) => const CanvasScreen())
    : HwOpenRoute(
        builder: (_) => const CanvasScreen(),
        origin: origin,
        cover: NotebookCover(
          color: Color(entry.metadata.coverColor),
          title: entry.metadata.title,
          texture: coverTextureFor(entry.metadata.paperType),
          style: CoverStyle.fromKey(entry.metadata.coverStyle),
          width: origin.width,
          height: origin.height,
        ));

Future<void> _openNotebookAndNavigate(
  BuildContext context,
  WidgetRef ref,
  NotebookEntry entry,
  Rect? origin,
  int token,
) async {
  final l10n = AppLocalizations.of(context);
  // A download from an unreachable server can take minutes: the user may
  // walk away from it. System back is blocked because the pop below would
  // then close the library instead of the loader.
  var loaderOpen = true;
  void dismissLoader() {
    if (!loaderOpen) return;
    loaderOpen = false;
    Navigator.of(context).pop();
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dctx) => PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.nbOpeningNotebook),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _openGate.cancel(token);
                  loaderOpen = false;
                  Navigator.of(dctx).pop();
                },
                child: Text(l10n.libCancel),
              ),
            ]),
          ),
        ),
      ),
    ),
  );

  /// After an await: true when the user cancelled. Only closes the canvas if
  /// no newer open took over, which would replace it itself.
  Future<bool> abandoned() async {
    if (_openGate.isCurrent(token)) return false;
    if (_openGate.cancelledWithoutSuccessor(token)) {
      await ref.read(canvasProvider.notifier).closeNotebook();
    }
    return true;
  }

  try {
    final syncService = ref.read(syncServiceProvider);
    final fileService = ref.read(fileServiceProvider);

    const kLazyThresholdBytes = 512 * 1024;
    const kLazyThresholdPages = 15;

    // ── Fast path: load straight from the loose store ──
    //
    // The loose store is the local source of truth after migration. Reading +
    // parsing it on a background isolate (with synchronous reads) avoids the
    // ~1700 sequential async file-read round-trips that, on the open-time
    // congested main event loop, took 10-20 s on 300-700 page notebooks — and
    // avoids the old "assemble the whole notebook into a ZIP then decode it
    // again" round trip entirely.
    if (syncService != null) {
      final dir = fileService.notebookStoreDir(entry.metadata.id);
      final id = entry.metadata.id;
      // The whole notebook loads in the background; the page it opens on
      // comes first, so the editor appears on it while the rest arrives.
      final full = syncService.loadLooseStoreFromDisk(dir);
      LooseStoreStart? start;
      try {
        final prefs = await SharedPreferences.getInstance();
        start = await syncService.loadLooseStoreStart(dir,
            prefs.getString('last_chapter_$id'), prefs.getInt('last_page_$id') ?? 0);
      } catch (_) {}
      if (start != null) {
        if (await abandoned()) return;
        final notifier = ref.read(canvasProvider.notifier);
        await notifier.showLoadingSnapshot(
          metadata: start.metadata,
          document: start.document,
          pages: start.pages,
          assets: start.assets,
          chapterId: start.chapterId,
          pageIndex: start.pageIndex,
          remotePath: entry.remotePath,
        );
        if (await abandoned() || !context.mounted) return;
        dismissLoader();
        final editor = Navigator.of(context).push(_editorRoute(origin, entry));
        final data = await full;
        // The user may have left the editor meanwhile.
        if (!notifier.isLoadingSnapshotOf(id)) {
          await editor;
          return;
        }
        if (data != null &&
            !(data.pages.isEmpty && data.document.pages.isNotEmpty)) {
          await notifier.openNotebook(
            metadata: data.metadata,
            document: data.document,
            pages: data.pages,
            remotePath: entry.remotePath,
            assets: data.assets,
            symbolLibraries: data.symbolLibraries.isNotEmpty
                ? data.symbolLibraries
                    .map((j) => SymbolLibrary.fromJson(j))
                    .toList()
                : null,
          );
          await editor;
          return;
        }
        // A page did not parse: leave the opening page and recover below,
        // as an open without it would.
        await notifier.closeNotebook();
        if (context.mounted) Navigator.of(context).pop();
        await editor;
        if (!context.mounted) return;
      }
      final data = start == null ? await full : null;
      if (data != null) {
        final corrupted =
            data.pages.isEmpty && data.document.pages.isNotEmpty;
        if (!corrupted) {
          if (await abandoned()) return;
          await ref.read(canvasProvider.notifier).openNotebook(
                metadata: data.metadata,
                document: data.document,
                pages: data.pages,
                remotePath: entry.remotePath,
                assets: data.assets,
                symbolLibraries: data.symbolLibraries.isNotEmpty
                    ? data.symbolLibraries
                        .map((j) => SymbolLibrary.fromJson(j))
                        .toList()
                    : null,
              );

          if (await abandoned() || !context.mounted) return;
          dismissLoader();
          await Navigator.of(context).push(_editorRoute(origin, entry));
          return;
        }
        // Corrupted loose store (no pages but document expects them) — fall
        // through to the legacy-file / server-download recovery below.
      }
    }

    Uint8List? localData = await fileService.readNotebookFile(entry.metadata.id);

    if (localData != null && syncService != null) {
      SyncService.validateNcnoteArchive(localData,
          context: 'open ${entry.metadata.title}');
      final parsed = syncService.parseNcnoteMetadata(localData);
      final isLarge = localData.lengthInBytes > kLazyThresholdBytes ||
          parsed.document.pages.length > kLazyThresholdPages;

      // Single-pass extraction: pages + assets + symbols in one ZIP walk
      // (and one isolate hop for large notebooks) instead of three
      // separate decodes / two isolate spawns of the same buffer.
      final contents = isLarge
          ? await syncService.extractNotebookContentsIsolated(localData)
          : syncService.extractNotebookContents(localData);
      final pages = contents.pages;
      final assets = contents.assets;
      final symbols = contents.symbolLibraries;

      final corrupted = pages.isEmpty && parsed.document.pages.isNotEmpty;
      if (!corrupted) {
        if (await abandoned()) return;
        await ref.read(canvasProvider.notifier).openNotebook(
              metadata: parsed.metadata,
              document: parsed.document,
              pages: pages,
              remotePath: entry.remotePath,
              assets: assets,
              symbolLibraries: symbols.isNotEmpty
                  ? symbols.map((j) => SymbolLibrary.fromJson(j)).toList()
                  : null,
            );

        if (await abandoned() || !context.mounted) return;
        dismissLoader();
        await Navigator.of(context).push(_editorRoute(origin, entry));
        return;
      }
    }

    if (syncService == null || syncService.isOffline) {
      throw NoLocalCopyOfflineException();
    }

    final result =
        await syncService.downloadExplodedFull(entry.metadata.id);

    try {
      final bytes = SyncService.buildPackageBytes(
        metadata: result.metadata,
        document: result.document,
        pages: result.pages,
        assets: result.assets,
        symbolLibraries: result.symbolLibraries,
      );
      await fileService.saveNotebookFile(result.metadata.id, bytes);
      await fileService.upsertNotebookMeta(
        id: result.metadata.id,
        title: result.metadata.title,
        remotePath: entry.remotePath,
        localModifiedAt: result.metadata.modifiedAt,
        syncStatus: 'synced',
        fileSize: bytes.length,
        coverColor: result.metadata.coverColor,
        coverStyle: result.metadata.coverStyle,
        paperType: result.metadata.paperType,
        pageCount: result.metadata.pageCount,
        createdAt: result.metadata.createdAt,
      );
      // Opening it is the user asking for it back: the notebook is on this
      // device now, so the "don't download this one" flag no longer describes
      // reality and would make the badge lie.
      await fileService.setNotebookDownloadSkipped(result.metadata.id, false);
    } catch (e) {
      debugPrint('[NotebookOpener] persist after download failed: $e');
    }

    if (await abandoned()) return;
    await ref.read(canvasProvider.notifier).openNotebook(
          metadata: result.metadata,
          document: result.document,
          pages: result.pages,
          remotePath: entry.remotePath,
          assets: result.assets,
          symbolLibraries: result.symbolLibraries.isNotEmpty
              ? result.symbolLibraries
                  .map((j) => SymbolLibrary.fromJson(j))
                  .toList()
              : null,
        );

    if (await abandoned() || !context.mounted) return;
    dismissLoader();
    await Navigator.of(context).push(_editorRoute(origin, entry));
  } catch (e) {
    if (!context.mounted || !_openGate.isCurrent(token)) return;
    dismissLoader();
    // Typed exceptions carry no user-facing text: localize them here, at the
    // point of display. Everything else falls back to the generic message.
    final String message;
    // A stub has nothing to open without the download.
    final unreachable = entry.notOnDevice &&
        (e is SocketException || e is TimeoutException || e is http.ClientException);
    if (e is NoLocalCopyOfflineException || unreachable) {
      message = l10n.nbNoLocalCopyOffline;
    } else if (e is FormatTooNewException) {
      message = l10n.cvFormatTooNew(e.fileVersion, e.supportedVersion);
    } else if (e is FormatException ||
        e is CorruptedArchiveException ||
        e is TypeError) {
      debugPrint('[NotebookOpener] corrupt notebook ${entry.metadata.id}: $e');
      message = l10n.qlOpenCorrupt;
    } else {
      message = l10n.nbOpenFailed('$e');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
