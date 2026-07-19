import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Lightweight connectivity monitor.
///
/// Periodically pings the Nextcloud server and exposes a ValueNotifier
/// so the UI and sync engine can react to online/offline transitions.
class ConnectivityService {
  final String serverHost;
  final int serverPort;

  Timer? _pollTimer;
  final ValueNotifier<bool> isOnline = ValueNotifier(false);

  /// Fires once when transitioning offline → online.
  void Function()? onReconnected;

  ConnectivityService({required this.serverHost, this.serverPort = 80});

  /// Start periodic connectivity checks.
  void startMonitoring({Duration interval = const Duration(seconds: 15)}) {
    _check(); // immediate first check
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _check());
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _check() async {
    final wasOnline = isOnline.value;
    try {
      final socket = await Socket.connect(
        serverHost,
        serverPort,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      isOnline.value = true;

      if (!wasOnline) {
        debugPrint('[Connectivity] Back online!');
        onReconnected?.call();
      }
    } catch (_) {
      isOnline.value = false;
      if (wasOnline) {
        debugPrint('[Connectivity] Gone offline.');
      }
    }
  }

  /// One-shot connectivity check.
  Future<bool> checkNow() async {
    await _check();
    return isOnline.value;
  }

  void dispose() {
    stopMonitoring();
    isOnline.dispose();
  }
}
