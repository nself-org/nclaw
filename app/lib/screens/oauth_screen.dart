import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/claw_action.dart';
import '../providers/action_provider.dart';

/// Screen shown when an OAuth re-authentication action is received.
///
/// Displays the provider name, a brief explanation, and buttons to
/// open the OAuth flow or deny the request.
class OAuthScreen extends ConsumerWidget {
  final ClawAction action;

  const OAuthScreen({super.key, required this.action});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = action.params['provider'] as String? ?? 'Unknown';
    final providerDisplay = _providerDisplayName(provider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Authentication Required'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),

            // Provider icon/name
            Icon(
              _providerIcon(provider),
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),

            Text(
              '$providerDisplay needs re-authentication',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            Text(
              'Your $providerDisplay session has expired. '
              'Tap "Authenticate" to sign in again. '
              'This will open your browser briefly.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Session info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Provider', providerDisplay),
                    if (action.params['scope'] case final String scope)
                      _infoRow('Scope', scope),
                    _infoRow('Session', action.sessionId.length > 8
                        ? '${action.sessionId.substring(0, 8)}...'
                        : action.sessionId),
                    _infoRow(
                      'Expires',
                      _formatExpiry(action.expiresAt),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Action buttons
            FilledButton.icon(
              onPressed: () => _approve(context, ref),
              icon: const Icon(Icons.login),
              label: const Text('Authenticate'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _deny(context, ref),
              child: const Text('Deny'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(actionProvider.notifier);
    await notifier.approve(action.id);
    if (context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _deny(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(actionProvider.notifier);
    await notifier.deny(action.id);
    if (context.mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  String _formatExpiry(DateTime expiry) {
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inHours > 0) return '${remaining.inHours}h remaining';
    return '${remaining.inMinutes}m remaining';
  }

  String _providerDisplayName(String provider) {
    return switch (provider.toLowerCase()) {
      'google' => 'Google',
      'github' => 'GitHub',
      'microsoft' => 'Microsoft',
      'apple' => 'Apple',
      'slack' => 'Slack',
      'discord' => 'Discord',
      _ => provider,
    };
  }

  IconData _providerIcon(String provider) {
    // Material icons don't have brand logos, so use generic auth icons.
    return switch (provider.toLowerCase()) {
      'google' => Icons.g_mobiledata,
      'github' => Icons.code,
      'microsoft' => Icons.window,
      'apple' => Icons.apple,
      _ => Icons.lock_open,
    };
  }
}
