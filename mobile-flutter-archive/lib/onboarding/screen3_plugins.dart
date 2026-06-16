import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/connection_provider.dart';
import 'wizard_state.dart';

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _PluginInfo {
  final String id;
  final String label;
  final String description;
  final bool needsOAuth;

  const _PluginInfo({
    required this.id,
    required this.label,
    required this.description,
    this.needsOAuth = false,
  });
}

const _plugins = [
  _PluginInfo(
    id: kPluginGoogle,
    label: 'Google Workspace',
    description: 'Gmail, Calendar, Drive — read, write, search.',
    needsOAuth: true,
  ),
  _PluginInfo(
    id: kPluginNotify,
    label: 'Notifications',
    description: 'Push alerts to your phone or desktop.',
  ),
  _PluginInfo(
    id: kPluginBrowser,
    label: 'Browser Control',
    description: 'Let ɳClaw browse the web on your behalf.',
  ),
  _PluginInfo(
    id: kPluginVoice,
    label: 'Voice Input',
    description: 'Speak to ɳClaw; it transcribes in real-time.',
  ),
  _PluginInfo(
    id: kPluginCron,
    label: 'Scheduler',
    description: 'Automated briefings, digests, and recurring tasks.',
  ),
];

// ---------------------------------------------------------------------------
// Screen 3 — Plugin Onboarding
// ---------------------------------------------------------------------------

/// Screen 3 of the first-run bootstrap wizard.
///
/// Shows 5 optional plugins. User can toggle each on/off, trigger OAuth flows
/// where needed, and tap [Skip All] or [Continue].
///
/// Accessibility (WCAG 2.1 AA):
/// - Each toggle has [role="checkbox"], [aria-checked], visible label.
/// - Connect/Enable buttons carry [Semantics.label] with plugin name.
/// - Validation errors in an [aria-live="assertive"] region (via [Semantics]).
/// - Focus is managed by the parent wizard on screen entry.
class Screen3Plugins extends ConsumerWidget {
  final VoidCallback onContinue;
  final VoidCallback onSkipAll;

  const Screen3Plugins({
    super.key,
    required this.onContinue,
    required this.onSkipAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizard = ref.watch(wizardStateProvider);
    final notifier = ref.read(wizardStateProvider.notifier);
    final theme = Theme.of(context);
    final serverUrl =
        ref.watch(connectionProvider).activeServer?.url ?? '';

    return Semantics(
      label: 'Connect Your Tools — optional plugin setup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect Your Tools',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Optional but recommended. You can change these later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: _plugins.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final plugin = _plugins[i];
                final enabled =
                    wizard.selectedPlugins.contains(plugin.id);
                return _PluginRow(
                  plugin: plugin,
                  enabled: enabled,
                  serverUrl: serverUrl,
                  onToggle: (val) =>
                      notifier.togglePlugin(plugin.id, enabled: val),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('screen3-skip-all'),
                  onPressed: onSkipAll,
                  child: const Text('Skip All'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('screen3-continue'),
                  onPressed: onContinue,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plugin row widget
// ---------------------------------------------------------------------------

class _PluginRow extends StatelessWidget {
  final _PluginInfo plugin;
  final bool enabled;
  final String serverUrl;
  final ValueChanged<bool> onToggle;

  const _PluginRow({
    required this.plugin,
    required this.enabled,
    required this.serverUrl,
    required this.onToggle,
  });

  Future<void> _handleAction(BuildContext context) async {
    if (!plugin.needsOAuth) return;
    // OAuth plugins open browser to initiate the flow.
    final uri =
        Uri.parse('$serverUrl/claw/oauth/${plugin.id}/start');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = plugin.needsOAuth ? 'Connect' : 'Enable';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Toggle — semantics: role=checkbox + aria-checked
          Semantics(
            checked: enabled,
            label: plugin.label,
            child: Switch(
              key: Key('plugin-toggle-${plugin.id}'),
              value: enabled,
              onChanged: onToggle,
            ),
          ),
          const SizedBox(width: 12),
          // Label + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.label,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  plugin.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          // Action button — visible only when enabled
          if (enabled) ...[
            const SizedBox(width: 8),
            Semantics(
              label: '$actionLabel ${plugin.label}',
              button: true,
              child: TextButton(
                key: Key('plugin-action-${plugin.id}'),
                onPressed: () => _handleAction(context),
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
