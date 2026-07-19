import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Opens a notebook: loads it (local first, server fallback), populates
/// canvasProvider, then pushes the editor screen. Mirrors the legacy
/// flow so the new UI inherits all the corruption-recovery logic.
Future<void> openNotebookAndNavigate(
  BuildContext context,
  WidgetRef ref,
  NotebookEntry entry,
) async {
  final l10n = AppLocalizations.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.nbOpeningNotebook),
          ]),
        ),
      ),
    ),
  );

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
      final data = await syncService.loadLooseStoreFromDisk(dir);
      if (data != null) {
        final corrupted =
            data.pages.isEmpty && data.document.pages.isNotEmpty;
        if (!corrupted) {
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

          if (!context.mounted) return;
          Navigator.of(context).pop(); // dismiss the loader
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CanvasScreen(),
          ));
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

        if (!context.mounted) return;
        Navigator.of(context).pop(); // dismiss the loader
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const CanvasScreen(),
        ));
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
        paperType: result.metadata.paperType,
        pageCount: result.metadata.pageCount,
        createdAt: result.metadata.createdAt,
      );
    } catch (e) {
      debugPrint('[NotebookOpener] persist after download failed: $e');
    }

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

    if (!context.mounted) return;
    Navigator.of(context).pop();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const CanvasScreen(),
    ));
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    // Typed exceptions carry no user-facing text: localize them here, at the
    // point of display. Everything else falls back to the generic message.
    final String message;
    if (e is NoLocalCopyOfflineException) {
      message = l10n.nbNoLocalCopyOffline;
    } else if (e is FormatTooNewException) {
      message = l10n.cvFormatTooNew(e.fileVersion, e.supportedVersion);
    } else {
      message = l10n.nbOpenFailed('$e');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
