/// T-1197: FCM push notification service for ɳClaw.
///
/// Handles Firebase Cloud Messaging initialization, foreground message display,
/// background message routing, and tap-to-navigate behaviour.
///
/// Usage (call once from main() before runApp):
///   await NotificationService.initialize(navigatorKey: _navigatorKey);
///
/// Background message handler must be a top-level function:
///
/// ```dart
/// @pragma('vm:entry-point')
/// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
///   await Firebase.initializeApp();
///   await NotificationService.handleBackground(msg);
/// }
/// // Register before runApp:
/// FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
/// ```
///
/// Route payload conventions (from server data payload):
///   {"route": "/digest"}    — navigate to DigestViewerScreen
///   {"route": "/health"}    — navigate to Health snapshot screen
///   {"route": "/memories"}  — navigate to MemoriesScreen
///
/// FCM token is surfaced via [NotificationService.tokenStream] so that
/// NotificationPermissionService (T-1198) can register it with the server.

library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show GlobalKey, NavigatorState, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ---------------------------------------------------------------------------
// Background handler — must be top-level (registered in main.dart)
// ---------------------------------------------------------------------------

/// Top-level FCM background message handler.
///
/// Called when a data-only or notification message arrives while the app is
/// in the background or terminated. Keep this fast — no UI allowed here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Re-initialise Firebase in the isolate (required).
  await Firebase.initializeApp();
  NotificationService._handleMessage(message, fromBackground: true);
}

// ---------------------------------------------------------------------------
// NotificationService
// ---------------------------------------------------------------------------

class NotificationService {
  NotificationService._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static final _tokenController = StreamController<String>.broadcast();

  /// Emits the current FCM token and any refreshed tokens.
  /// Listen in T-1198 to register with the server.
  static Stream<String> get tokenStream => _tokenController.stream;

  /// Android notification channel for proactive ɳClaw alerts.
  static const _channel = AndroidNotificationChannel(
    'nclaw_proactive',
    'ɳClaw Alerts',
    description: 'Morning digest, health reports, and proactive alerts.',
    importance: Importance.high,
  );

  /// Initialize FCM and local notifications.
  ///
  /// Call once from main() after [Firebase.initializeApp()].
  /// Pass a [GlobalKey<NavigatorState>] to enable tap-to-navigate.
  static Future<void> initialize({
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    // Set up local notification channel (Android).
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        _routeFromPayload(details.payload, navigatorKey);
      },
    );

    // Request permission (iOS — Android 13+ is handled in T-1198).
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Emit current token.
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) _tokenController.add(token);

    // Emit refreshed tokens.
    FirebaseMessaging.instance.onTokenRefresh.listen(_tokenController.add);

    // Foreground messages — show as local notification since FCM suppresses
    // heads-up displays while the app is in the foreground.
    FirebaseMessaging.onMessage.listen((message) {
      _handleMessage(message, fromBackground: false);
    });

    // Tapped notification (app was in background, not terminated).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _routeFromMessage(message, navigatorKey);
    });

    // Cold start — app was terminated when notification arrived.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Delay routing until the first frame is rendered.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _routeFromMessage(initial, navigatorKey);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static void _handleMessage(
    RemoteMessage message, {
    required bool fromBackground,
  }) {
    final notification = message.notification;

    if (fromBackground) {
      // Background — local notification already shown by FCM on Android.
      // Nothing extra to do unless we want custom routing data in the payload.
      return;
    }

    // Foreground — show via flutter_local_notifications.
    if (notification == null && message.data.isEmpty) return;

    final title = notification?.title ??
        message.data['title'] ??
        '\u0273Claw';
    final body = notification?.body ??
        message.data['body'] ??
        '';

    // Encode the route payload so we can navigate on tap.
    final payload = message.data['route'] != null
        ? jsonEncode({'route': message.data['route']})
        : null;

    _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static void _routeFromMessage(
    RemoteMessage message,
    GlobalKey<NavigatorState>? navigatorKey,
  ) {
    final route = message.data['route'] as String?;
    if (route == null || navigatorKey == null) return;
    _pushRoute(route, navigatorKey);
  }

  static void _routeFromPayload(
    String? payload,
    GlobalKey<NavigatorState>? navigatorKey,
  ) {
    if (payload == null || navigatorKey == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final route = data['route'] as String?;
      if (route != null) _pushRoute(route, navigatorKey);
    } catch (_) {}
  }

  static void _pushRoute(
    String route,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    debugPrint('[NotificationService] navigating to $route');
    navigator.pushNamed(route);
  }
}
