import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/claw_action.dart';
import '../providers/action_provider.dart';

/// Detail screen for a single action showing full params, status timeline,
/// and result display.
class ActionDetailScreen extends ConsumerWidget {
  final String actionId;

  const ActionDetailScreen({super.key, required this.actionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(actionProvider);

    // Find the action across all lists.
    final action = _findAction(actionState, actionId);

    if (action == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Action')),
        body: const Center(child: Text('Action not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_typeLabel(action.type)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status timeline.
          _StatusTimeline(action: action),
          const SizedBox(height: 24),

          // Action type and ID.
          _SectionHeader(title: 'Details'),
          const SizedBox(height: 8),
          _DetailRow(label: 'ID', value: action.id),
          _DetailRow(label: 'Session', value: action.sessionId),
          _DetailRow(label: 'Type', value: _typeLabel(action.type)),
          _DetailRow(
            label: 'Created',
            value: _formatDateTime(action.createdAt),
          ),
          if (action.executedAt != null)
            _DetailRow(
              label: 'Executed',
              value: _formatDateTime(action.executedAt!),
            ),
          _DetailRow(
            label: 'Expires',
            value: _formatDateTime(action.expiresAt),
          ),
          const SizedBox(height: 24),

          // Parameters (pretty-printed JSON).
          _SectionHeader(title: 'Parameters'),
          const SizedBox(height: 8),
          _JsonBlock(data: action.params),
          const SizedBox(height: 24),

          // Result (if available).
          if (action.result != null) ...[
            _SectionHeader(title: 'Result'),
            const SizedBox(height: 8),
            _JsonBlock(data: action.result!),
            const SizedBox(height: 24),
          ],

          // Action buttons.
          if (action.isPending)
            _ActionButtons(
              onApprove: () {
                ref.read(actionProvider.notifier).approve(action.id);
                Navigator.of(context).pop();
              },
              onDeny: () {
                ref.read(actionProvider.notifier).deny(action.id);
                Navigator.of(context).pop();
              },
            ),
          if (action.status == ActionStatus.failed)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.read(actionProvider.notifier).retry(action.id);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),

          // Bottom padding for safe area.
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  ClawAction? _findAction(ActionQueueState state, String id) {
    for (final action in state.pending) {
      if (action.id == id) return action;
    }
    for (final action in state.active) {
      if (action.id == id) return action;
    }
    for (final action in state.history) {
      if (action.id == id) return action;
    }
    return null;
  }

  String _typeLabel(ActionType type) => switch (type) {
        ActionType.fileOp => 'File Operation',
        ActionType.oauth => 'OAuth Request',
        ActionType.shell => 'Shell Command',
        ActionType.browser => 'Open Browser',
        ActionType.notification => 'Notification',
      };

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} $h:$m:$s';
  }
}

/// Visual timeline showing the lifecycle stages of an action.
class _StatusTimeline extends StatelessWidget {
  final ClawAction action;

  const _StatusTimeline({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _buildSteps();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            ...List.generate(steps.length, (i) {
              final step = steps[i];
              final isLast = i == steps.length - 1;
              return _TimelineStep(
                label: step.label,
                isCompleted: step.completed,
                isCurrent: step.current,
                isLast: isLast,
              );
            }),
          ],
        ),
      ),
    );
  }

  List<_Step> _buildSteps() {
    final status = action.status;
    return [
      _Step(
        label: 'Created',
        completed: true,
        current: status == ActionStatus.pending,
      ),
      _Step(
        label: 'Approved',
        completed: status.index >= ActionStatus.approved.index &&
            status != ActionStatus.failed &&
            status != ActionStatus.expired,
        current: status == ActionStatus.approved,
      ),
      _Step(
        label: 'Executing',
        completed: status == ActionStatus.done ||
            (status == ActionStatus.executing),
        current: status == ActionStatus.executing,
      ),
      _Step(
        label: status == ActionStatus.failed
            ? 'Failed'
            : status == ActionStatus.expired
                ? 'Expired'
                : 'Done',
        completed: status == ActionStatus.done ||
            status == ActionStatus.failed ||
            status == ActionStatus.expired,
        current: status == ActionStatus.done ||
            status == ActionStatus.failed ||
            status == ActionStatus.expired,
      ),
    ];
  }
}

class _Step {
  final String label;
  final bool completed;
  final bool current;

  const _Step({
    required this.label,
    required this.completed,
    required this.current,
  });
}

class _TimelineStep extends StatelessWidget {
  final String label;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLast;

  const _TimelineStep({
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isCompleted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.25);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent ? color : Colors.transparent,
                border: Border.all(color: color, width: 2),
              ),
              child: isCompleted && !isCurrent
                  ? Icon(Icons.check, size: 12, color: color)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: color,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isCompleted
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Section header for detail groups.
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

/// Key-value detail row.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pretty-printed JSON block with a monospace font and syntax-like coloring.
class _JsonBlock extends StatelessWidget {
  final Map<String, dynamic> data;

  const _JsonBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prettyJson =
        const JsonEncoder.withIndent('  ').convert(data);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        prettyJson,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Approve and deny button row.
class _ActionButtons extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  const _ActionButtons({
    required this.onApprove,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onDeny,
            child: const Text('Deny'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: onApprove,
            child: const Text('Approve'),
          ),
        ),
      ],
    );
  }
}
