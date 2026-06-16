/// E-26-01: Sidebar drawer with infinite nested topic tree.
///
/// Swipe from left to open. Long-press drag reorder with haptic feedback.
/// Color/icon pickers as bottom sheets.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../models/topic_node.dart';
import '../providers/topic_provider.dart';

/// The main drawer widget. Use as `Scaffold.drawer`.
class TopicDrawer extends ConsumerWidget {
  const TopicDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(topicTreeProvider);
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Text('Topics',
                      style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'New topic',
                    onPressed: () => _showCreateDialog(context, ref),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(child: _buildContent(context, ref, state, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    TopicTreeState state,
    ThemeData theme,
  ) {
    // Loading
    if (state.loading && state.topics.isEmpty) {
      return _SkeletonTree();
    }

    // Error
    if (state.error != null && state.topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text("Couldn't load topics",
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () =>
                  ref.read(topicTreeProvider.notifier).loadTopics(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Empty
    if (state.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.topic_outlined, size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('No topics yet',
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New topic'),
            ),
          ],
        ),
      );
    }

    // Populated tree
    return RefreshIndicator(
      onRefresh: () => ref.read(topicTreeProvider.notifier).loadTopics(),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final topic in state.topics)
            _TopicNodeTile(
              node: topic,
              selectedId: state.selectedTopicId,
            ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Topic'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Topic name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref.read(topicTreeProvider.notifier)
                  .createTopic(name: value.trim());
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(topicTreeProvider.notifier)
                    .createTopic(name: name);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Single topic row: 32px height, indented by depth, color dot, icon,
/// name, unread badge. Expand/collapse children. Long-press for drag.
class _TopicNodeTile extends ConsumerWidget {
  final TopicNode node;
  final String? selectedId;

  const _TopicNodeTile({
    required this.node,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isSelected = node.id == selectedId;
    final indent = 16.0 + (node.depth * 20.0);
    final hasChildren = node.children.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LongPressDraggable<String>(
          data: node.id,
          feedback: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(node.name, style: theme.textTheme.bodyMedium),
            ),
          ),
          onDragStarted: () => HapticFeedback.mediumImpact(),
          child: DragTarget<String>(
            onAcceptWithDetails: (details) {
              HapticFeedback.heavyImpact();
              ref.read(topicTreeProvider.notifier).reorderTopic(
                    topicId: details.data,
                    newParentId: node.id,
                    newSortOrder: 0,
                  );
            },
            builder: (context, candidateData, rejectedData) {
              final isDropTarget = candidateData.isNotEmpty;
              return Semantics(
                label: _buildSemanticLabel(node),
                selected: isSelected,
                button: true,
                hint: hasChildren
                    ? (node.isExpanded ? 'Tap to collapse' : 'Tap to expand')
                    : 'Tap to open',
                child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(topicTreeProvider.notifier).selectTopic(node.id);
                  if (hasChildren) {
                    ref.read(topicTreeProvider.notifier)
                        .toggleExpanded(node.id);
                  }
                  // Close drawer and navigate.
                  Navigator.of(context).pop();
                },
                onLongPress: () => _showTopicOptions(context, ref),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.3)
                        : isDropTarget
                            ? theme.colorScheme.primary
                                .withValues(alpha: 0.1)
                            : null,
                  ),
                  padding: EdgeInsets.only(left: indent, right: 8),
                  child: Row(
                    children: [
                      // Expand/collapse arrow
                      if (hasChildren)
                        Icon(
                          node.isExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 18,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        )
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 4),

                      // Color dot
                      if (node.color != null)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: _parseColor(node.color!),
                            shape: BoxShape.circle,
                          ),
                        ),

                      // Icon or emoji
                      if (node.icon != null) ...[
                        Text(node.icon!, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                      ],

                      // Name
                      Expanded(
                        child: Text(
                          node.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Unread badge — excluded from a11y tree (count
                      // is already included in the parent Semantics label).
                      if (node.unreadCount > 0)
                        ExcludeSemantics(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${node.unreadCount}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              );
            },
          ),
        ), // LongPressDraggable
        // Children (expanded)
        if (hasChildren && node.isExpanded)
          ...node.children.map(
            (child) => _TopicNodeTile(node: child, selectedId: selectedId),
          ),
      ],
    );
  }

  String _buildSemanticLabel(TopicNode node) {
    final buf = StringBuffer(node.name);
    if (node.unreadCount > 0) {
      buf.write(', ${node.unreadCount} unread');
    }
    if (node.children.isNotEmpty) {
      buf.write(node.isExpanded ? ', expanded' : ', collapsed');
    }
    return buf.toString();
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF0EA5E9);
  }

  void _showTopicOptions(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.palette),
              title: const Text('Change color'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showColorPicker(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions),
              title: const Text('Change icon'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showIconPicker(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add subtopic'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showCreateSubtopic(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context, WidgetRef ref) {
    final colors = [
      '#0EA5E9', '#EF4444', '#F59E0B', '#10B981', '#3B82F6',
      '#8B5CF6', '#EC4899', '#F97316', '#14B8A6', '#64748B',
    ];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((hex) {
              return GestureDetector(
                onTap: () {
                  ref.read(topicTreeProvider.notifier)
                      .updateTopic(topicId: node.id, color: hex);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _parseColor(hex),
                    shape: BoxShape.circle,
                    border: node.color == hex
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showIconPicker(BuildContext context, WidgetRef ref) {
    final icons = [
      '\u{1F4AC}', '\u{1F4BC}', '\u{1F3E0}', '\u{2764}', '\u{1F4DA}',
      '\u{1F680}', '\u{1F3AF}', '\u{1F4A1}', '\u{1F527}', '\u{1F30D}',
      '\u{1F3B5}', '\u{1F4F7}', '\u{2708}', '\u{1F4B0}', '\u{1F393}',
    ];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: icons.map((emoji) {
              return GestureDetector(
                onTap: () {
                  ref.read(topicTreeProvider.notifier)
                      .updateTopic(topicId: node.id, icon: emoji);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showCreateSubtopic(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New subtopic of ${node.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Subtopic name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(topicTreeProvider.notifier)
                    .createTopic(name: name, parentId: node.id);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Skeleton loading for the topic tree.
class _SkeletonTree extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade800,
      highlightColor: Colors.grey.shade700,
      child: ListView.builder(
        itemCount: 8,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (_, index) {
          final indent = 16.0 + ((index % 3) * 20.0);
          return Padding(
            padding: EdgeInsets.only(left: indent, right: 16, top: 4, bottom: 4),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        },
      ),
    );
  }
}
