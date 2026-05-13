import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/oauth_service.dart';
import 'action_provider.dart';
import 'connection_provider.dart';

/// Provides the [OAuthService] instance, wired to the shared queue and client.
final oauthServiceProvider = Provider<OAuthService>((ref) {
  final queueService = ref.watch(actionQueueServiceProvider);
  final client = ref.watch(connectionProvider.notifier).client;

  final service = OAuthService(
    queueService: queueService,
    client: client,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Stream of OAuth completion results for UI snackbars/notifications.
final oauthResultProvider = StreamProvider<OAuthResult>((ref) {
  final service = ref.watch(oauthServiceProvider);
  return service.onComplete;
});
