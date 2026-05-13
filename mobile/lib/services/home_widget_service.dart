/// E-26-07: Home screen widget data provider.
///
/// Provides data for iOS WidgetKit and Android AppWidgetProvider via
/// the home_widget package. Three widget sizes: small (3 recent),
/// medium (3 recent + quick capture), large (5 recent + 2 nudges).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'offline_cache_service.dart';

class HomeWidgetService {
  /// Update widget data with recent conversations.
  /// Called on app background and periodically via workmanager.
  static Future<void> updateWidgetData() async {
    try {
      final cache = OfflineCacheService.instance;
      final conversations = await cache.getCachedConversations();

      // Take up to 5 most recent conversations.
      final recent = conversations.take(5).toList();

      final widgetData = {
        'recent_conversations': recent
            .map((c) => {
                  'id': c['id'],
                  'title': c['title'] ?? c['name'] ?? 'Untitled',
                  'last_message': c['last_message'] ?? '',
                  'updated_at': c['updated_at'] ?? '',
                })
            .toList(),
        'pending_count': await cache.pendingWriteCount(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _writeWidgetData(jsonEncode(widgetData));
    } catch (e) {
      debugPrint('[HomeWidgetService] Failed to update widget data: $e');
    }
  }

  /// Write data to shared storage accessible by native widget.
  static Future<void> _writeWidgetData(String jsonData) async {
    try {
      await HomeWidget.saveWidgetData<String>('widget_topics', jsonData);
      await HomeWidget.updateWidget(
        name: 'ClawWidget',
        androidName: 'ClawWidget',
        iOSName: 'ClawWidget',
      );
    } catch (e) {
      debugPrint('[HomeWidgetService] Widget update failed: $e');
    }
  }
}
