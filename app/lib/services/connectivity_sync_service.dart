/// S22-T09: Reconnect-triggered offline sync.
///
/// Subscribes to connectivity_plus and, when the device transitions from
/// offline to any online state, runs [BackgroundSyncService.execute] so
/// any queued writes flush immediately — without waiting for the 15-minute
/// workmanager cadence.
///
/// The service is idempotent and safe to re-initialize. It debounces
/// rapid offline/online toggles (flaky cellular) by gating on a 3-second
/// quiet window before firing a sync.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'background_sync_service.dart';

class ConnectivitySyncService {
  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static Timer? _debounce;
  static bool _wasOnline = true;
  static String? _serverUrl;

  /// Begin listening. [resolveServerUrl] is called lazily each sync so the
  /// active server from ConnectionProvider is always current.
  static Future<void> start(String? Function() resolveServerUrl) async {
    await stop();

    // Prime current state.
    final initial = await Connectivity().checkConnectivity();
    _wasOnline = _hasAnyConnection(initial);

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = _hasAnyConnection(results);
      if (online && !_wasOnline) {
        // Offline → online transition; debounce before syncing.
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 3), () async {
          _serverUrl = resolveServerUrl();
          if (_serverUrl == null) return;
          debugPrint(
              '[ConnectivitySync] Reconnect detected — flushing queue');
          await BackgroundSyncService.execute(_serverUrl);
        });
      }
      _wasOnline = online;
    });
  }

  static Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
    await _sub?.cancel();
    _sub = null;
  }

  static bool _hasAnyConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
