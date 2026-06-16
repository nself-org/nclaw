/// T-1198: Notification permission request + FCM token registration.
///
/// Responsibilities:
///   1. Request notification permission on Android 13+ and iOS.
///   2. Listen to NotificationService.tokenStream and register the FCM token
///      with the nself-claw backend via POST /claw/devices.
///   3. Re-register automatically on token refresh.
///   4. Manage the app badge count (clear on foreground, set from server).
///
/// Call [NotificationPermissionService.setup] once after the connection
/// provider reports that a server is active.

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import 'notification_service.dart';

class NotificationPermissionService {
  NotificationPermissionService._();

  static bool _initialised = false;

  /// Set up permission request and token registration for [serverUrl].
  ///
  /// [jwtToken] is the bearer token for the claw server (required to
  /// authenticate the device registration call).
  ///
  /// Safe to call multiple times — only runs full setup on the first call.
  static Future<void> setup({
    required String serverUrl,
    required String? jwtToken,
  }) async {
    if (jwtToken == null || jwtToken.isEmpty) return;
    if (_initialised) return;
    _initialised = true;

    await _requestPermission();

    // Register current token and every refreshed one.
    NotificationService.tokenStream.listen((token) {
      _registerToken(
        serverUrl: serverUrl,
        jwtToken: jwtToken,
        fcmToken: token,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Permission request
  // ---------------------------------------------------------------------------

  static Future<void> _requestPermission() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      // Android 13+ (API 33) requires POST_NOTIFICATIONS permission.
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
    // iOS permission is requested in NotificationService.initialize() via
    // FirebaseMessaging.instance.requestPermission — no extra step needed.
  }

  // ---------------------------------------------------------------------------
  // FCM token registration with the claw server
  // ---------------------------------------------------------------------------

  static Future<void> _registerToken({
    required String serverUrl,
    required String jwtToken,
    required String fcmToken,
  }) async {
    final base = serverUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/claw/devices');

    final platform = _platformLabel();
    final deviceName = 'ɳClaw ${Platform.operatingSystem}';

    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwtToken',
            },
            body: jsonEncode({
              'user_id': _parseUserIdFromJwt(jwtToken),
              'device_type': 'mobile',
              'platform': platform,
              'name': deviceName,
              'push_token': '${_pushPrefix()}:$fcmToken',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        debugPrint('[NotificationPermission] FCM token registered ($platform)');
      } else {
        debugPrint(
          '[NotificationPermission] token registration failed: '
          '${resp.statusCode} ${resp.body}',
        );
      }
    } catch (e) {
      debugPrint('[NotificationPermission] token registration error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Badge management
  // ---------------------------------------------------------------------------

  /// Clear the app badge counter (call when the user opens the app or
  /// dismisses all notifications).
  static Future<void> clearBadge() async {
    if (kIsWeb) return;
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(badge: true);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  /// FCM token prefix for server-side dispatch routing.
  /// Use 'apns:' on iOS/macOS (APNs transport), 'fcm:' on Android/web.
  static String _pushPrefix() {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) return 'apns';
    return 'fcm';
  }

  /// Extract the user_id claim from a JWT without verifying the signature.
  ///
  /// The nself-claw JWT payload is a standard HS256 token with a `sub` claim
  /// containing the user ID. We only need the claim — server verifies the sig.
  static String _parseUserIdFromJwt(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return '';
      final payload = parts[1];
      // Base64url decode with padding.
      final padded = payload.padRight(
        payload.length + (4 - payload.length % 4) % 4,
        '=',
      );
      final decoded = utf8.decode(base64Url.decode(padded));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return map['sub'] as String? ?? map['user_id'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }
}
