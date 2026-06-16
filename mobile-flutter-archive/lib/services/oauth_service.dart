import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../models/claw_action.dart';
import 'action_queue_service.dart';
import 'claw_client.dart';

/// Handles OAuth re-authentication actions dispatched by the nself-claw backend.
///
/// When the backend needs the user to re-authenticate with an OAuth provider
/// (e.g., Google token expired), it dispatches an `oauth` action with the
/// authorization URL. This service:
///
/// 1. Opens the OAuth URL in the platform's in-app browser
///    (SFSafariViewController on iOS, Custom Tabs on Android)
/// 2. Listens for the deep link callback
/// 3. Sends the auth code/token back to the server
class OAuthService {
  final ActionQueueService _queueService;
  final ClawClient _client;

  /// Stream controller for OAuth completion events.
  final _completionController =
      StreamController<OAuthResult>.broadcast();

  /// Fires when an OAuth flow completes (success or failure).
  Stream<OAuthResult> get onComplete => _completionController.stream;

  OAuthService({
    required ActionQueueService queueService,
    required ClawClient client,
  })  : _queueService = queueService,
        _client = client;

  /// Handle an incoming OAuth action from the action queue.
  ///
  /// Expected params:
  /// - `url` (String): The OAuth authorization URL to open
  /// - `provider` (String): The OAuth provider name (google, github, etc.)
  /// - `callbackScheme` (String?): Custom URL scheme for the redirect
  Future<void> handleOAuthAction(ClawAction action) async {
    final url = action.params['url'] as String?;
    final provider = action.params['provider'] as String? ?? 'unknown';

    if (url == null || url.isEmpty) {
      await _queueService.updateStatus(
        action.id,
        ActionStatus.failed,
        result: {'error': 'Missing OAuth URL in action params'},
      );
      _completionController.add(OAuthResult(
        actionId: action.id,
        provider: provider,
        success: false,
        error: 'Missing OAuth URL',
      ));
      return;
    }

    // Mark action as executing.
    await _queueService.updateStatus(action.id, ActionStatus.executing);

    // Notify server that we're starting the OAuth flow.
    _client.send({
      'type': 'action_status',
      'actionId': action.id,
      'status': 'executing',
    });

    try {
      final uri = Uri.parse(url);

      // Use launchUrl with in-app browser mode.
      // iOS: SFSafariViewController, Android: Custom Tabs.
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );

      if (!launched) {
        // Fallback to external browser.
        final externalLaunch = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!externalLaunch) {
          throw Exception('Could not launch OAuth URL');
        }
      }

      // The OAuth redirect will come back via deep link.
      // The app's deep link handler (configured in main.dart or platform config)
      // should call completeOAuth() when it receives the callback.

    } catch (e) {
      await _queueService.updateStatus(
        action.id,
        ActionStatus.failed,
        result: {'error': 'Failed to open OAuth URL: $e'},
      );

      _client.send({
        'type': 'action_result',
        'actionId': action.id,
        'status': 'failed',
        'result': {'error': 'Failed to open OAuth URL: $e'},
      });

      _completionController.add(OAuthResult(
        actionId: action.id,
        provider: provider,
        success: false,
        error: e.toString(),
      ));
    }
  }

  /// Called when the OAuth redirect deep link is received.
  ///
  /// [actionId] identifies which OAuth action this completes.
  /// [callbackUrl] is the full redirect URL containing the auth code/token.
  Future<void> completeOAuth({
    required String actionId,
    required Uri callbackUrl,
  }) async {
    final code = callbackUrl.queryParameters['code'];
    final error = callbackUrl.queryParameters['error'];
    final state = callbackUrl.queryParameters['state'];

    if (error != null) {
      await _queueService.updateStatus(
        actionId,
        ActionStatus.failed,
        result: {'error': 'OAuth denied: $error'},
      );

      _client.send({
        'type': 'action_result',
        'actionId': actionId,
        'status': 'failed',
        'result': {'error': 'OAuth denied: $error'},
      });

      _completionController.add(OAuthResult(
        actionId: actionId,
        provider: 'unknown',
        success: false,
        error: 'OAuth denied: $error',
      ));
      return;
    }

    if (code == null) {
      await _queueService.updateStatus(
        actionId,
        ActionStatus.failed,
        result: {'error': 'No auth code in callback'},
      );

      _client.send({
        'type': 'action_result',
        'actionId': actionId,
        'status': 'failed',
        'result': {'error': 'No auth code in callback'},
      });

      _completionController.add(OAuthResult(
        actionId: actionId,
        provider: 'unknown',
        success: false,
        error: 'No auth code in callback',
      ));
      return;
    }

    // Send the auth code back to the server for token exchange.
    await _queueService.updateStatus(
      actionId,
      ActionStatus.done,
      result: {'code': code, 'state': state},
    );

    _client.send({
      'type': 'action_result',
      'actionId': actionId,
      'status': 'done',
      'result': {
        'code': code,
        if (state != null) 'state': state,
        'callback_url': callbackUrl.toString(),
      },
    });

    _completionController.add(OAuthResult(
      actionId: actionId,
      provider: 'unknown',
      success: true,
    ));
  }

  void dispose() {
    _completionController.close();
  }
}

/// Result of an OAuth flow attempt.
class OAuthResult {
  final String actionId;
  final String provider;
  final bool success;
  final String? error;

  const OAuthResult({
    required this.actionId,
    required this.provider,
    required this.success,
    this.error,
  });
}
