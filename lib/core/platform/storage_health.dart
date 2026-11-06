import 'dart:io';

import 'package:flutter/foundation.dart';

/// Native builds write straight to disk; there is nothing to watch.
final ValueListenable<String?> browserStorageError = ValueNotifier(null);

/// Whether [error] from a local write means the disk is full
/// (ENOSPC on POSIX, ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL on Windows).
bool isOutOfSpace(Object error) {
  if (error is! FileSystemException) return false;
  final code = error.osError?.errorCode;
  return code == 28 || code == 112 || code == 39;
}
