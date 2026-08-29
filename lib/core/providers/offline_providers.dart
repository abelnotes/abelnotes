import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/services/connectivity_service.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/symbol_library_service.dart';
import 'package:abelnotes/core/services/thumbnail_service.dart';

/// Singleton FileService provider — must be initialized before use.
final fileServiceProvider = Provider<FileService>((ref) {
  return FileService();
});

/// Singleton ThumbnailService — caches page previews to disk.
final thumbnailServiceProvider = Provider<ThumbnailService>((ref) {
  return ThumbnailService();
});

/// ConnectivityService provider — depends on server URL from credentials.
final connectivityServiceProvider = Provider<ConnectivityService?>((ref) {
  final creds = ref.watch(credentialsProvider);
  if (creds == null) return null;

  final uri = Uri.parse(creds.serverUrl);
  final service = ConnectivityService(
    serverHost: uri.host,
    serverPort: uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// The device-wide symbol library — one per app, not per notebook.
///
/// Kept alive for the whole session (it caches the collection and the remote
/// version token), and reads the remote store through a callback rather than
/// watching it: rebuilding this provider every time the backend setting
/// changes would throw away that cache and re-download the library.
final symbolLibraryServiceProvider = Provider<SymbolLibraryService>((ref) {
  final service = SymbolLibraryService(
    fileService: ref.watch(fileServiceProvider),
    remoteStore: () => ref.read(remoteStoreProvider),
  );
  // Switching backend points at a different remote, whose version token has
  // nothing to do with the old one's — force the next reconcile to re-read.
  ref.listen(remoteStoreProvider, (_, __) => service.forgetRemoteVersion());
  return service;
});
