import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/claw_action.dart';

/// Executes approved [ClawAction]s on the local device.
///
/// Supported action types:
/// - [ActionType.browser]: opens a URL with url_launcher
/// - [ActionType.fileOp]: reads/writes/lists/deletes files in the app's
///   Documents directory (sandboxed — no path traversal)
/// - [ActionType.notification]: shows a local notification via
///   flutter_local_notifications
/// - [ActionType.shell]: not supported on mobile — returns an error result
/// - [ActionType.oauth]: opens the OAuth authorization URL in the platform
///   browser; the actual token exchange completes asynchronously via the
///   deep link callback handled by [OAuthService]
class ActionExecutorService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  /// Executes [action] and returns a result map.
  ///
  /// Never throws — returns `{'error': description}` on failure.
  Future<Map<String, dynamic>> execute(ClawAction action) async {
    try {
      return switch (action.type) {
        ActionType.browser      => await _executeBrowser(action),
        ActionType.fileOp       => await _executeFileOp(action),
        ActionType.notification => await _executeNotification(action),
        ActionType.shell        => await _executeShell(action),
        ActionType.oauth        => await _executeOAuth(action),
      };
    } catch (e, st) {
      debugPrint('[ActionExecutor] error executing ${action.type}: $e\n$st');
      return {'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // Browser
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _executeBrowser(ClawAction action) async {
    final url = action.params['url'] as String?;
    if (url == null || url.isEmpty) {
      return {'error': 'browser action missing url param'};
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return {'error': 'invalid URL: $url'};
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return {'launched': launched, 'url': url};
  }

  // ---------------------------------------------------------------------------
  // File operations
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _executeFileOp(ClawAction action) async {
    final op = action.params['op'] as String? ?? 'read';
    final path = action.params['path'] as String?;

    if (path == null) {
      return {'error': 'fileOp action missing path param'};
    }

    // All file ops are sandboxed to the app's documents directory.
    final docsDir = await getApplicationDocumentsDirectory();
    final sandboxRoot = docsDir.path;

    // Resolve against sandbox root and verify no path traversal.
    final resolved = File('$sandboxRoot/$path').absolute;
    if (!resolved.path.startsWith(sandboxRoot)) {
      return {'error': 'path traversal denied: $path'};
    }

    switch (op) {
      case 'read':
        if (!await resolved.exists()) {
          return {'error': 'file not found: $path'};
        }
        final content = await resolved.readAsString();
        return {'content': content, 'path': resolved.path};

      case 'write':
        final content = action.params['content'] as String? ?? '';
        await resolved.parent.create(recursive: true);
        await resolved.writeAsString(content);
        return {'written': true, 'path': resolved.path, 'bytes': content.length};

      case 'list':
        final dir = Directory(resolved.path);
        if (!await dir.exists()) {
          return {'error': 'directory not found: $path'};
        }
        final entries = await dir.list().map((e) => e.path).toList();
        return {'entries': entries, 'count': entries.length};

      case 'delete':
        if (!await resolved.exists()) {
          return {'error': 'file not found: $path'};
        }
        await resolved.delete();
        return {'deleted': true, 'path': resolved.path};

      default:
        return {'error': 'unknown fileOp: $op'};
    }
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _executeNotification(ClawAction action) async {
    await _ensureNotificationsInitialized();

    final title = action.params['title'] as String? ?? 'ɳClaw';
    final body  = action.params['body']  as String? ?? '';

    const androidDetails = AndroidNotificationDetails(
      'nclaw_actions',
      'ɳClaw Actions',
      channelDescription: 'Notifications from ɳClaw action execution',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _notifications.show(id, title, body, details);
    return {'notified': true, 'title': title};
  }

  static Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(initSettings);
    _notificationsInitialized = true;
  }

  // ---------------------------------------------------------------------------
  // Shell (not supported on mobile)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _executeShell(ClawAction action) async {
    // T-1064: Shell not supported on this platform
    debugPrint('[ActionExecutor] shell action requested but not supported on this platform');

    await _ensureNotificationsInitialized();

    const androidDetails = AndroidNotificationDetails(
      'nclaw_actions',
      'ɳClaw Actions',
      channelDescription: 'Notifications from ɳClaw action execution',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _notifications.show(
      id,
      'Action not supported',
      "Action type 'shell' is not supported on this device.",
      details,
    );

    return {'error': 'shell execution is not supported on mobile'};
  }

  // ---------------------------------------------------------------------------
  // OAuth
  //
  // Opens the OAuth authorization URL in the platform browser.
  // The actual token exchange completes asynchronously when the app receives
  // the deep link callback — that completion is handled by OAuthService, which
  // has access to the ClawClient and ActionQueueService needed to send the
  // result back to the server.
  //
  // This method returns {'pending': true} on success so the caller can set the
  // action status to 'executing' (awaiting callback) rather than 'done'.
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _executeOAuth(ClawAction action) async {
    final authUrl = action.params['url'] as String?
        ?? action.params['auth_url'] as String?;
    final provider = action.params['provider'] as String? ?? 'unknown';

    if (authUrl == null || authUrl.isEmpty) {
      return {'error': 'oauth action missing url param'};
    }

    final uri = Uri.tryParse(authUrl);
    if (uri == null) {
      return {'error': 'invalid OAuth URL: $authUrl'};
    }

    // Try in-app browser first (SFSafariViewController / Custom Tabs).
    bool launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!launched) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (!launched) {
      return {'error': 'could not launch OAuth URL: $authUrl'};
    }

    // Return pending — OAuthService.completeOAuth() will send the final result
    // once the deep link callback is received.
    return {'pending': true, 'provider': provider, 'url': authUrl};
  }
}
