import 'package:flutter/material.dart';

import '../models/claw_action.dart';

/// Reusable card widget for displaying a single action in the queue.
///
/// Shows the action type icon, description, timestamp, and status chip.
/// Optionally shows approve/deny buttons for pending actions.
class ActionCard extends StatelessWidget {
  final ClawAction action;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;

  const ActionCard({
    super.key,
    required this.action,
    this.onTap,
    this.onApprove,
    this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Action type icon.
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _typeColor(theme).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _typeIcon,
                      size: 20,
                      color: _typeColor(theme),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title and description.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeLabel,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status chip.
                  _StatusChip(status: action.status),
                ],
              ),
              // Timestamp row.
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 52),
                child: Text(
                  _formatTime(action.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ),
              // Approve/deny buttons for pending actions.
              if (action.isPending && (onApprove != null || onDeny != null))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onDeny != null)
                        TextButton(
                          onPressed: onDeny,
                          child: const Text('Deny'),
                        ),
                      const SizedBox(width: 8),
                      if (onApprove != null)
                        FilledButton(
                          onPressed: onApprove,
                          child: const Text('Approve'),
                        ),
                    ],
                  ),
                ),
              // Progress indicator for executing actions.
              if (action.status == ActionStatus.executing)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _typeIcon => switch (action.type) {
        ActionType.fileOp => Icons.folder_outlined,
        ActionType.oauth => Icons.key_outlined,
        ActionType.shell => Icons.terminal,
        ActionType.browser => Icons.open_in_browser,
        ActionType.notification => Icons.notifications_outlined,
      };

  String get _typeLabel => switch (action.type) {
        ActionType.fileOp => 'File Operation',
        ActionType.oauth => 'OAuth Request',
        ActionType.shell => 'Shell Command',
        ActionType.browser => 'Open Browser',
        ActionType.notification => 'Notification',
      };

  Color _typeColor(ThemeData theme) => switch (action.type) {
        ActionType.fileOp => Colors.blue,
        ActionType.oauth => Colors.orange,
        ActionType.shell => Colors.green,
        ActionType.browser => Colors.purple,
        ActionType.notification => theme.colorScheme.primary,
      };

  String get _description {
    // Build a human-readable description from the params.
    final params = action.params;
    return switch (action.type) {
      ActionType.fileOp =>
        params['path'] as String? ?? params['operation'] as String? ?? 'File operation',
      ActionType.oauth =>
        params['provider'] as String? ?? 'Authentication request',
      ActionType.shell =>
        params['command'] as String? ?? 'Shell command',
      ActionType.browser =>
        params['url'] as String? ?? 'Open URL',
      ActionType.notification =>
        params['message'] as String? ?? params['title'] as String? ?? 'Notification',
    };
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.month}/${time.day}/${time.year}';
  }
}

/// Small colored chip showing the action's current status.
class _StatusChip extends StatelessWidget {
  final ActionStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color get _color => switch (status) {
        ActionStatus.pending => Colors.amber,
        ActionStatus.approved => Colors.blue,
        ActionStatus.executing => Colors.blue,
        ActionStatus.done => Colors.green,
        ActionStatus.failed => Colors.red,
        ActionStatus.expired => Colors.grey,
      };

  String get _label => switch (status) {
        ActionStatus.pending => 'Pending',
        ActionStatus.approved => 'Approved',
        ActionStatus.executing => 'Running',
        ActionStatus.done => 'Done',
        ActionStatus.failed => 'Failed',
        ActionStatus.expired => 'Expired',
      };
}
