/// E-26-06: Push notification service (FCM + APNs).
///
/// Handles token registration, foreground display, background tap deep-links,
/// Android channels per category, iOS thread grouping.
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// Notification payload from the backend notify plugin.
class ClawNotification {
  final String kind; // 'message', 'memory', 'action', 'digest'
  final String title;
  final String body;
  final String? deepLink; // e.g. 'nclaw://chat?id=xxx'
  final String? threadId; // iOS thread grouping

  const ClawNotification({
    required this.kind,
    required this.title,
    required this.body,
    this.deepLink,
    this.threadId,
  });

  factory ClawNotification.fromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    return ClawNotification(
      kind: data['kind'] ?? 'message',
      title: message.notification?.title ?? data['title'] ?? '',
      body: message.notification?.body ?? data['body'] ?? '',
      deepLink: data['deep_link'],
      threadId: data['thread_id'],
    );
  }
}

class PushNotificationService {
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static final _messaging = FirebaseMessaging.instance;

  /// Android notification channels per kind.
  static const _channels = {
    'message': AndroidNotificationChannel(
      'nclaw_messages',
      'Messages',
      description: 'New message notifications',
      importance: Importance.high,
    ),
    'memory': AndroidNotificationChannel(
      'nclaw_memory',
      'Memory',
      description: 'Memory extraction notifications',
      importance: Importance.defaultImportance,
    ),
    'action': AndroidNotificationChannel(
      'nclaw_actions',
      'Actions',
      description: 'Action queue notifications',
      importance: Importance.high,
    ),
    'digest': AndroidNotificationChannel(
      'nclaw_digest',
      'Digest',
      description: 'Daily digest notifications',
      importance: Importance.low,
    ),
  };

  /// Initialize push notification handling.
  static Future<void> initialize({
    required void Function(String deepLink) onDeepLink,
  }) async {
    // Request permissions (iOS).
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Create Android channels.
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      for (final channel in _channels.values) {
        await androidPlugin.createNotificationChannel(channel);
      }
    }

    // Initialize local notifications.
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) {
          onDeepLink(payload);
        }
      },
    );

    // Foreground messages.
    FirebaseMessaging.onMessage.listen((message) {
      _showLocalNotification(
          ClawNotification.fromRemoteMessage(message));
    });

    // Background tap (app was in background).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final notification = ClawNotification.fromRemoteMessage(message);
      if (notification.deepLink != null) {
        onDeepLink(notification.deepLink!);
      }
    });

    // Cold-start tap (app was terminated).
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      final notification = ClawNotification.fromRemoteMessage(initial);
      if (notification.deepLink != null) {
        onDeepLink(notification.deepLink!);
      }
    }
  }

  /// Register device token with backend.
  static Future<void> registerToken(String serverUrl) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      await http.post(
        Uri.parse('$serverUrl/claw/devices/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        }),
      );
    } catch (e) {
      debugPrint('[PushNotificationService] Token registration failed: $e');
    }

    // Listen for token refresh.
    _messaging.onTokenRefresh.listen((newToken) async {
      try {
        await http.post(
          Uri.parse('$serverUrl/claw/devices/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': newToken,
            'platform': defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
          }),
        );
      } catch (_) {}
    });
  }

  /// Show a local notification for a foreground message.
  static Future<void> _showLocalNotification(
      ClawNotification notification) async {
    final channel =
        _channels[notification.kind] ?? _channels['message']!;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          groupKey: notification.threadId,
        ),
        iOS: DarwinNotificationDetails(
          threadIdentifier: notification.threadId,
        ),
      ),
      payload: notification.deepLink,
    );
  }
}
