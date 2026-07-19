import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/services/connectivity_service.dart';
import 'package:abelnotes/core/services/file_service.dart';
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
