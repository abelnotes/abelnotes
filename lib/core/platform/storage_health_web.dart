import 'package:flutter/foundation.dart';

import 'package:abelnotes/core/platform/io_web.dart';

/// Set when the browser refused a write to the local store (out of space).
ValueListenable<String?> get browserStorageError =>
    WebFs.instance.persistError;

/// The browser reports a full store through [browserStorageError] instead.
bool isOutOfSpace(Object error) => false;
