import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/claw_action.dart';
import '../providers/action_provider.dart';
import '../widgets/action_card.dart';
import 'action_detail_screen.dart';

/// Tabbed screen showing all actions: Pending, Active, and History.
class ActionListScreen extends ConsumerWidget {
  const ActionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(actionProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Actions'),
          bottom: TabBar(
            tabs: [
              Tab(
                child: Badge(
                  label: Text('${actionState.pendingCount}'),
                  isLabelVisible: actionState.pendingCount > 0,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Pending'),
                  ),
                ),
              ),
              Tab(
                child: Badge(
                  label: Text('${actionState.active.length}'),
                  isLabelVisible: actionState.active.isNotEmpty,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Active'),
                  ),
                ),
              ),
              const Tab(text: 'History'),
            ],
          ),
        ),
        body: actionState.loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _PendingTab(actions: actionState.pending, ref: ref),
                  _ActiveTab(actions: actionState.active),
                  _HistoryTab(actions: actionState.history, ref: ref),
                ],
              ),
      ),
    );
  }
}

/// Pending tab: actions awaiting user approval with approve/deny buttons.
class _PendingTab extends StatelessWidget {
  final List<ClawAction> actions;
  final WidgetRef ref;

  const _PendingTab({required this.actions, required this.ref});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline,
        title: 'No pending actions',
        subtitle: 'Actions from the server will appear here for your approval.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(actionProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionCard(
            action: action,
            onTap: () => _openDetail(context, action),
            onApprove: () =>
                ref.read(actionProvider.notifier).approve(action.id),
            onDeny: () => ref.read(actionProvider.notifier).deny(action.id),
          );
        },
      ),
    );
  }
}

/// Active tab: actions currently being executed with progress indicators.
class _ActiveTab extends StatelessWidget {
  final List<ClawAction> actions;

  const _ActiveTab({required this.actions});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return _EmptyState(
        icon: Icons.hourglass_empty,
        title: 'No active actions',
        subtitle: 'Actions being executed will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return ActionCard(
          action: action,
          onTap: () => _openDetail(context, action),
        );
      },
    );
  }
}

/// History tab: completed, failed, or expired actions with result previews.
class _HistoryTab extends StatelessWidget {
  final List<ClawAction> actions;
  final WidgetRef ref;

  const _HistoryTab({required this.actions, required this.ref});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return _EmptyState(
        icon: Icons.history,
        title: 'No history yet',
        subtitle: 'Completed actions will be recorded here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(actionProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionCard(
            action: action,
            onTap: () => _openDetail(context, action),
          );
        },
      ),
    );
  }
}

/// Empty state placeholder shown when a tab has no actions.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openDetail(BuildContext context, ClawAction action) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ActionDetailScreen(actionId: action.id),
    ),
  );
}
