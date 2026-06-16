import 'package:flutter/material.dart';

/// Card widget displaying the current AI model configuration status.
///
/// Shows:
/// - Local model name and readiness state (ready / downloading / none)
/// - Number of linked Gemini accounts
/// - Number of configured API keys
///
/// Tap the card to invoke [onTap].
class ModelStatusCard extends StatelessWidget {
  final String? localModel;

  /// One of: `ready`, `downloading`, `none`.
  final String localModelStatus;

  final int geminiAccounts;
  final int apiKeyCount;
  final VoidCallback? onTap;

  const ModelStatusCard({
    required this.localModel,
    required this.localModelStatus,
    required this.geminiAccounts,
    required this.apiKeyCount,
    this.onTap,
    super.key,
  });

  Color _modelStatusColor(BuildContext context) {
    return switch (localModelStatus) {
      'ready' => Colors.green,
      'downloading' => Colors.amber,
      _ => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
    };
  }

  IconData get _modelStatusIcon {
    return switch (localModelStatus) {
      'ready' => Icons.check_circle,
      'downloading' => Icons.downloading,
      _ => Icons.remove_circle_outline,
    };
  }

  String get _modelStatusLabel {
    return switch (localModelStatus) {
      'ready' => 'Ready',
      'downloading' => 'Downloading',
      _ => 'Not installed',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _modelStatusColor(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI Configuration',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (onTap != null) ...[
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // Local model row
              _StatusRow(
                icon: _modelStatusIcon,
                iconColor: statusColor,
                label: localModel != null && localModel!.isNotEmpty
                    ? localModel!
                    : 'Local model',
                trailing: _modelStatusLabel,
                trailingColor: statusColor,
              ),
              const SizedBox(height: 8),
              // Gemini accounts row
              _StatusRow(
                icon: Icons.account_circle_outlined,
                iconColor: geminiAccounts > 0
                    ? Colors.blue
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                label: 'Gemini',
                trailing:
                    '$geminiAccounts ${geminiAccounts == 1 ? 'account' : 'accounts'}',
                trailingColor: geminiAccounts > 0
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 8),
              // API keys row
              _StatusRow(
                icon: Icons.key_outlined,
                iconColor: apiKeyCount > 0
                    ? Colors.orange
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                label: 'API keys',
                trailing:
                    '$apiKeyCount ${apiKeyCount == 1 ? 'key' : 'keys'}',
                trailingColor: apiKeyCount > 0
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String trailing;
  final Color trailingColor;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.trailing,
    required this.trailingColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          trailing,
          style: theme.textTheme.bodySmall?.copyWith(color: trailingColor),
        ),
      ],
    );
  }
}
