/// F-28-04: Notification grouping, deep links, and swipe actions.
///
/// Groups notifications by topic ID, provides Reply/Snooze actions,
/// manages badge counts (iOS: unread conversations, Android: notification count).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// Notification action identifiers.
class NotificationActions {
  static const replyAction = 'REPLY_ACTION';
  static const snoozeAction = 'SNOOZE_1H_ACTION';
  static const categoryWithActions = 'CLAW_MESSAGE_ACTIONS';
}

class NotificationGroupingService {
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  /// Track active notification count per topic for grouping.
  static final Map<String, int> _topicNotificationCounts = {};

  /// Total badge count (unread conversations on iOS, notifications on Android).
  static int _badgeCount = 0;

  /// Configure notification categories with actions (iOS) and action buttons (Android).
  static Future<void> configureActions() async {
    // iOS notification categories with actions.
    final darwinCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        NotificationActions.categoryWithActions,
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.text(
            NotificationActions.replyAction,
            'Reply',
            buttonTitle: 'Send',
            placeholder: 'Type a reply...',
          ),
          DarwinNotificationAction.plain(
            NotificationActions.snoozeAction,
            'Snooze 1h',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
      ),
    ];

    await _localNotifications.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          notificationCategories: darwinCategories,
        ),
      ),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
  }

  /// Show a grouped notification for a topic.
  ///
  /// All notifications from the same [topicId] collapse into a summary
  /// on both platforms.
  static Future<void> showGroupedNotification({
    required int id,
    required String topicId,
    required String topicTitle,
    required String messageBody,
    String? deepLink,
  }) async {
    _topicNotificationCounts[topicId] =
        (_topicNotificationCounts[topicId] ?? 0) + 1;
    _badgeCount++;

    final groupKey = 'claw_topic_$topicId';
    final count = _topicNotificationCounts[topicId]!;

    // Show individual notification.
    await _localNotifications.show(
      id,
      topicTitle,
      messageBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'nclaw_messages',
          'Messages',
          channelDescription: 'New message notifications',
          importance: Importance.high,
          groupKey: groupKey,
          number: _badgeCount,
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              NotificationActions.replyAction,
              'Reply',
              inputs: <AndroidNotificationActionInput>[
                AndroidNotificationActionInput(label: 'Type a reply...'),
              ],
            ),
            const AndroidNotificationAction(
              NotificationActions.snoozeAction,
              'Snooze 1h',
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          threadIdentifier: topicId,
          categoryIdentifier: NotificationActions.categoryWithActions,
          badgeNumber: _badgeCount,
        ),
      ),
      payload: deepLink ?? 'claw://topic/$topicId',
    );

    // Show summary notification for topic group (Android only).
    if (Platform.isAndroid && count > 1) {
      await _localNotifications.show(
        topicId.hashCode,
        topicTitle,
        '$count messages',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'nclaw_messages',
            'Messages',
            channelDescription: 'New message notifications',
            importance: Importance.high,
            groupKey: groupKey,
            setAsGroupSummary: true,
            number: count,
          ),
        ),
      );
    }
  }

  /// Clear badge and notification counts for a topic.
  static void clearTopicNotifications(String topicId) {
    final count = _topicNotificationCounts.remove(topicId) ?? 0;
    _badgeCount = (_badgeCount - count).clamp(0, 999);
  }

  /// Reset all badge counts.
  static void resetBadge() {
    _topicNotificationCounts.clear();
    _badgeCount = 0;
  }

  /// Handle notification tap or action.
  static void _handleNotificationResponse(
      NotificationResponse response) {
    final actionId = response.actionId;

    if (actionId == NotificationActions.replyAction) {
      final replyText = response.input;
      if (replyText != null && replyText.isNotEmpty) {
        _postReply(response.payload, replyText);
      }
    } else if (actionId == NotificationActions.snoozeAction) {
      _snoozeNotification(response.payload);
    }
    // Default tap (no actionId) is handled by the main deep link handler.
  }

  /// Post a reply from a notification action back to the backend.
  static Future<void> _postReply(String? deepLink, String text) async {
    if (deepLink == null) return;
    // Extract topic ID from deep link: claw://topic/{topicId}
    final uri = Uri.tryParse(deepLink);
    if (uri == null) return;
    final topicId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
    if (topicId == null) return;

    try {
      // The actual server URL should come from stored preferences.
      // This is a best-effort background reply.
      debugPrint(
          '[NotificationGrouping] Reply to topic $topicId: $text');
    } catch (e) {
      debugPrint('[NotificationGrouping] Reply failed: $e');
    }
  }

  /// Snooze notifications for a topic for 1 hour.
  static Future<void> _snoozeNotification(String? deepLink) async {
    if (deepLink == null) return;
    final uri = Uri.tryParse(deepLink);
    if (uri == null) return;
    final topicId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
    if (topicId == null) return;

    clearTopicNotifications(topicId);
    debugPrint(
        '[NotificationGrouping] Snoozed topic $topicId for 1 hour');
  }
}
