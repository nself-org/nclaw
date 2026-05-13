/// E-26-03: Memory explorer with 4 tabs (Facts, Decisions, Entities, Timeline).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../models/memory_record.dart';
import '../providers/memory_explorer_provider.dart';

class MemoryExplorerScreen extends ConsumerWidget {
  const MemoryExplorerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Memory'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Facts'),
              Tab(text: 'Decisions'),
              Tab(text: 'Entities'),
              Tab(text: 'Timeline'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FactsTab(),
            _DecisionsTab(),
            _EntitiesTab(),
            _TimelineTab(),
          ],
        ),
      ),
    );
  }
}

// -- Facts Tab ---------------------------------------------------------------

class _FactsTab extends ConsumerWidget {
  const _FactsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memoryExplorerProvider);
    return _MemoryList(
      loading: state.loading,
      records: state.facts,
      error: state.error,
      emptyMessage: 'No facts recorded yet',
      onRefresh: () => ref.read(memoryExplorerProvider.notifier).loadAll(),
    );
  }
}

// -- Decisions Tab -----------------------------------------------------------

class _DecisionsTab extends ConsumerWidget {
  const _DecisionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memoryExplorerProvider);
    return _MemoryList(
      loading: state.loading,
      records: state.decisions,
      error: state.error,
      emptyMessage: 'No decisions recorded yet',
      showStatusBadge: true,
      onRefresh: () => ref.read(memoryExplorerProvider.notifier).loadAll(),
    );
  }
}

// -- Entities Tab ------------------------------------------------------------

class _EntitiesTab extends ConsumerWidget {
  const _EntitiesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memoryExplorerProvider);
    return _MemoryList(
      loading: state.loading,
      records: state.entities,
      error: state.error,
      emptyMessage: 'No entities discovered yet',
      onRefresh: () => ref.read(memoryExplorerProvider.notifier).loadAll(),
    );
  }
}

// -- Timeline Tab ------------------------------------------------------------

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memoryExplorerProvider);
    return _MemoryList(
      loading: state.loading,
      records: state.timeline,
      error: state.error,
      emptyMessage: 'No memories yet',
      showTimestamp: true,
      onRefresh: () => ref.read(memoryExplorerProvider.notifier).loadAll(),
    );
  }
}

// -- Shared List Widget ------------------------------------------------------

class _MemoryList extends StatelessWidget {
  final bool loading;
  final List<MemoryRecord> records;
  final String? error;
  final String emptyMessage;
  final bool showStatusBadge;
  final bool showTimestamp;
  final Future<void> Function() onRefresh;

  const _MemoryList({
    required this.loading,
    required this.records,
    this.error,
    required this.emptyMessage,
    this.showStatusBadge = false,
    this.showTimestamp = false,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Loading
    if (loading && records.isEmpty) {
      return Shimmer.fromColors(
        baseColor: Colors.grey.shade800,
        highlightColor: Colors.grey.shade700,
        child: ListView.builder(
          itemCount: 6,
          padding: const EdgeInsets.all(16),
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      );
    }

    // Error
    if (error != null && records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to load', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: onRefresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Empty
    if (records.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    // Populated
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: records.length,
        itemBuilder: (context, index) {
          final record = records[index];
          return _MemoryCard(
            record: record,
            showStatusBadge: showStatusBadge,
            showTimestamp: showTimestamp,
          );
        },
      ),
    );
  }
}

class _MemoryCard extends StatefulWidget {
  final MemoryRecord record;
  final bool showStatusBadge;
  final bool showTimestamp;

  const _MemoryCard({
    required this.record,
    this.showStatusBadge = false,
    this.showTimestamp = false,
  });

  @override
  State<_MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<_MemoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.record;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Type chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _typeColor(r.entityType)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      r.entityType,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _typeColor(r.entityType),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Status badge (decisions)
                  if (widget.showStatusBadge && r.status != null) ...[
                    _StatusBadge(status: r.status!),
                    const SizedBox(width: 8),
                  ],

                  const Spacer(),

                  // Confidence bar
                  SizedBox(
                    width: 40,
                    child: LinearProgressIndicator(
                      value: r.confidence,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'x${r.timesReinforced}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Content
              Text(
                r.content,
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),

              // Expanded details
              if (_expanded) ...[
                const SizedBox(height: 8),
                if (widget.showTimestamp)
                  Text(
                    'Created: ${r.createdAt.toLocal()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                if (r.source.isNotEmpty)
                  Text(
                    'Source: ${r.source}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
        'fact' => Colors.blue,
        'decision' => Colors.amber,
        'entity' => Colors.teal,
        _ => Colors.grey,
      };
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'active' => (Colors.green, 'Active'),
      'superseded' => (Colors.orange, 'Superseded'),
      'rejected' => (Colors.red, 'Rejected'),
      _ => (Colors.grey, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color),
      ),
    );
  }
}
