/// E-26-08c: Background sync service via workmanager.
///
/// Periodic 15-minute background task that:
/// 1. Flushes the write queue (pending offline operations)
/// 2. Syncs recent data from server to local cache
/// 3. Updates home screen widget data
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'home_widget_service.dart';
import 'offline_cache_service.dart';

class BackgroundSyncService {
  static const taskName = 'com.nself.nclaw.background_sync';

  /// Register periodic background sync.
  /// Call once during app initialization.
  ///
  /// F-28-07: Wires workmanager for 15-min periodic background sync
  /// that updates home screen widgets via HomeWidgetService.
  static Future<void> register() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      inputData: <String, dynamic>{},
    );
    debugPrint('[BackgroundSync] Periodic task registered (15 min interval)');
  }

  /// Execute the background sync.
  /// Called by workmanager callback or manually on app foreground.
  static Future<bool> execute(String? serverUrl) async {
    if (serverUrl == null) return false;

    try {
      // 1. Flush write queue.
      await _flushWriteQueue(serverUrl);

      // 2. Sync recent data.
      await _syncRecentData(serverUrl);

      // 3. Update home widget.
      await HomeWidgetService.updateWidgetData();

      return true;
    } catch (e) {
      debugPrint('[BackgroundSync] Sync failed: $e');
      return false;
    }
  }

  /// Flush pending writes from the offline queue.
  static Future<void> _flushWriteQueue(String serverUrl) async {
    final cache = OfflineCacheService.instance;
    final pending = await cache.getPendingWrites();

    for (final write in pending) {
      final id = write['id'] as int;
      final endpoint = write['endpoint'] as String;
      final method = write['method'] as String;
      final body = write['body'] as String?;

      try {
        final uri = Uri.parse('$serverUrl$endpoint');
        final headers = {'Content-Type': 'application/json'};

        late http.Response response;
        switch (method.toUpperCase()) {
          case 'POST':
            response = await http.post(uri, headers: headers, body: body);
          case 'PATCH':
            response = await http.patch(uri, headers: headers, body: body);
          case 'PUT':
            response = await http.put(uri, headers: headers, body: body);
          case 'DELETE':
            response = await http.delete(uri, headers: headers);
          default:
            await cache.markWriteFailed(id);
            continue;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await cache.markWriteComplete(id);
        } else {
          await cache.markWriteFailed(id);
        }
      } catch (_) {
        // Network still down; leave as pending for next sync.
      }
    }
  }

  /// Sync recent conversations and memories from server to local cache.
  static Future<void> _syncRecentData(String serverUrl) async {
    final cache = OfflineCacheService.instance;

    try {
      // Sync recent conversations.
      final convResponse = await http
          .get(Uri.parse('$serverUrl/claw/conversations?limit=20'))
          .timeout(const Duration(seconds: 10));

      if (convResponse.statusCode == 200) {
        final data = jsonDecode(convResponse.body) as List<dynamic>? ?? [];
        for (final conv in data) {
          final map = conv as Map<String, dynamic>;
          await cache.cacheConversation(map['id'] as String, map);
        }
      }

      // Sync recent memories.
      final memResponse = await http
          .get(Uri.parse('$serverUrl/claw/memory?limit=50'))
          .timeout(const Duration(seconds: 10));

      if (memResponse.statusCode == 200) {
        final data = jsonDecode(memResponse.body) as List<dynamic>? ?? [];
        await cache.cacheMemories(
          data.map((m) => m as Map<String, dynamic>).toList(),
        );
      }
    } catch (e) {
      debugPrint('[BackgroundSync] Data sync failed: $e');
    }
  }
}

/// Top-level callback for Workmanager. Must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == BackgroundSyncService.taskName) {
      final serverUrl = inputData?['server_url'] as String?;
      return BackgroundSyncService.execute(serverUrl);
    }
    return Future.value(true);
  });
}
