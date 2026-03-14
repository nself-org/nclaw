// T-1105: ThreadListScreen — sessions with tags, projects, search, grouping.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_provider.dart';

// ---------------------------------------------------------------------------
// Tag colour palette (matches KNOWN_TAGS in thread_intelligence.rs)
// ---------------------------------------------------------------------------

const _tagColors = {
  'code': Color(0xFF3B82F6),        // blue
  'infra': Color(0xFFF97316),       // orange
  'admin': Color(0xFFEF4444),       // red
  'personal': Color(0xFF22C55E),    // green
  'research': Color(0xFFA855F7),    // purple
  'question': Color(0xFF06B6D4),    // cyan
  'task': Color(0xFFEAB308),        // yellow
  'planning': Color(0xFF8B5CF6),    // violet
};

Color _tagColor(String tag) =>
    _tagColors[tag] ?? const Color(0xFF6B7280); // grey fallback

// ---------------------------------------------------------------------------
// Relative time helper
// ---------------------------------------------------------------------------

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Browse, search, and manage all chat threads.
///
/// Features:
/// - Grouped by project (section headers) with flat-list toggle
/// - Thread rows: title, tag chips, relative time, admin indicator
/// - Search bar with 300ms debounce → GET /claw/sessions/search
/// - Tag filter chips (horizontal scroll)
/// - Long press → context menu: Archive · Export markdown · Rename ·
///   Move to project
/// - Pull-to-refresh
/// - Empty state
class ThreadListScreen extends ConsumerStatefulWidget {
  /// Optional initial project filter.
  final String? filterProjectId;

  const ThreadListScreen({super.key, this.filterProjectId});

  @override
  ConsumerState<ThreadListScreen> createState() => _ThreadListScreenState();
}

class _ThreadListScreenState extends ConsumerState<ThreadListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _grouped = true;
  String? _activeTagFilter;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(chatProvider.notifier).searchSessions(_searchController.text);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(chatProvider.notifier).clearSearch();
  }

  // Build the list of sessions to display based on search / tag filter.
  List<ChatSession> _filtered(ChatState cs) {
    List<ChatSession> list;
    if (cs.searchQuery.isNotEmpty && cs.searchResults != null) {
      list = cs.searchResults!;
    } else {
      list = cs.sessions.where((s) => !s.isPending).toList();
    }

    // Apply project filter passed in from ProjectListScreen.
    if (widget.filterProjectId != null) {
      list = list
          .where((s) => s.projectId == widget.filterProjectId)
          .toList();
    }

    // Apply tag chip filter.
    if (_activeTagFilter != null) {
      list = list.where((s) => s.tags.contains(_activeTagFilter)).toList();
    }

    return list;
  }

  /// Collect all unique tags across visible sessions.
  List<String> _allTags(List<ChatSession> sessions) {
    final seen = <String>{};
    for (final s in sessions) {
      seen.addAll(s.tags);
    }
    return seen.toList()..sort();
  }

  // ---------------------------------------------------------------------------
  // Long-press context menu
  // ---------------------------------------------------------------------------

  void _showContextMenu(
    BuildContext context,
    ChatSession session,
    List<ChatProject> projects,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _SessionContextMenu(
        session: session,
        projects: projects,
        onArchive: () async {
          Navigator.pop(ctx);
          await ref.read(chatProvider.notifier).archiveSession(session.id);
        },
        onRename: () {
          Navigator.pop(ctx);
          _showRenameDialog(context, session);
        },
        onExport: () {
          Navigator.pop(ctx);
          _exportAsMarkdown(context, session);
        },
        onMoveToProject: (projectId) async {
          Navigator.pop(ctx);
          await ref
              .read(chatProvider.notifier)
              .moveSessionToProject(session.id, projectId);
        },
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ChatSession session) {
    final ctrl = TextEditingController(text: session.displayTitle);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename thread'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Thread title'),
          onSubmitted: (_) => _submitRename(ctx, session, ctrl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => _submitRename(ctx, session, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _submitRename(
      BuildContext context, ChatSession session, String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    Navigator.pop(context);
    await ref.read(chatProvider.notifier).renameSession(session.id, t);
  }

  void _exportAsMarkdown(BuildContext context, ChatSession session) {
    final buf = StringBuffer();
    buf.writeln('# ${session.displayTitle}');
    buf.writeln();
    for (final msg in session.messages) {
      final label = msg.role == 'user' ? '**You**' : '**ɳClaw**';
      buf.writeln('$label: ${msg.content}');
      buf.writeln();
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied as markdown')),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = ref.watch(chatProvider);
    final sessions = _filtered(cs);
    final tags = _allTags(sessions);
    final isSearching = cs.searchQuery.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Threads'),
        actions: [
          if (!isSearching)
            IconButton(
              icon: Icon(_grouped
                  ? Icons.format_list_bulleted
                  : Icons.folder_outlined),
              tooltip: _grouped ? 'Show flat list' : 'Group by project',
              onPressed: () => setState(() => _grouped = !_grouped),
            ),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchController,
            onClear: _clearSearch,
          ),
          if (tags.isNotEmpty) ...[
            _TagFilterBar(
              tags: tags,
              activeTag: _activeTagFilter,
              onTag: (tag) => setState(() {
                _activeTagFilter = _activeTagFilter == tag ? null : tag;
              }),
            ),
          ],
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(chatProvider.notifier).loadSessions();
              },
              child: sessions.isEmpty
                  ? _EmptyState(isSearching: isSearching)
                  : (_grouped && !isSearching && widget.filterProjectId == null)
                      ? _GroupedList(
                          sessions: sessions,
                          projects: cs.projects,
                          onTap: (s) => _openSession(context, s),
                          onLongPress: (s) =>
                              _showContextMenu(context, s, cs.projects),
                        )
                      : _FlatList(
                          sessions: sessions,
                          projects: cs.projects,
                          onTap: (s) => _openSession(context, s),
                          onLongPress: (s) =>
                              _showContextMenu(context, s, cs.projects),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSession(BuildContext context, ChatSession session) async {
    await ref.read(chatProvider.notifier).switchSession(session.id);
    if (context.mounted) Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;

  const _SearchBar({required this.controller, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search threads…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: onClear,
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tag filter bar
// ---------------------------------------------------------------------------

class _TagFilterBar extends StatelessWidget {
  final List<String> tags;
  final String? activeTag;
  final ValueChanged<String> onTag;

  const _TagFilterBar(
      {required this.tags, required this.activeTag, required this.onTag});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final tag = tags[i];
          final active = tag == activeTag;
          final color = _tagColor(tag);
          return FilterChip(
            label: Text(tag),
            labelStyle: TextStyle(
              fontSize: 11,
              color: active ? Colors.white : color,
              fontWeight: FontWeight.w500,
            ),
            selected: active,
            onSelected: (_) => onTag(tag),
            backgroundColor: color.withValues(alpha: 0.12),
            selectedColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread tile
// ---------------------------------------------------------------------------

class _ThreadTile extends StatelessWidget {
  final ChatSession session;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ThreadTile({
    required this.session,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = session.tags;
    final visibleTags = tags.take(2).toList();
    final overflow = tags.length - visibleTags.length;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        child: Icon(
          session.isAdminMode
              ? Icons.admin_panel_settings_outlined
              : Icons.chat_bubble_outline,
          size: 18,
          color: session.isAdminMode
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
      ),
      title: Text(
        session.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (visibleTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 4,
                children: [
                  ...visibleTags.map((t) => _TagChip(tag: t)),
                  if (overflow > 0)
                    _TagChip(tag: '+$overflow', color: const Color(0xFF6B7280)),
                ],
              ),
            ),
        ],
      ),
      trailing: Text(
        _relativeTime(session.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  final Color? color;

  const _TagChip({required this.tag, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? _tagColor(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          color: c,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Flat list
// ---------------------------------------------------------------------------

class _FlatList extends StatelessWidget {
  final List<ChatSession> sessions;
  final List<ChatProject> projects;
  final ValueChanged<ChatSession> onTap;
  final ValueChanged<ChatSession> onLongPress;

  const _FlatList({
    required this.sessions,
    required this.projects,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: sessions.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 60, endIndent: 16),
      itemBuilder: (_, i) => _ThreadTile(
        session: sessions[i],
        onTap: () => onTap(sessions[i]),
        onLongPress: () => onLongPress(sessions[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grouped list (by project)
// ---------------------------------------------------------------------------

class _GroupedList extends StatelessWidget {
  final List<ChatSession> sessions;
  final List<ChatProject> projects;
  final ValueChanged<ChatSession> onTap;
  final ValueChanged<ChatSession> onLongPress;

  const _GroupedList({
    required this.sessions,
    required this.projects,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group sessions: project buckets in order, then uncategorized.
    final Map<String?, List<ChatSession>> groups = {};
    for (final s in sessions) {
      (groups[s.projectId] ??= []).add(s);
    }

    final projectIds = projects.map((p) => p.id).toList();
    final orderedKeys = [
      ...projectIds.where(groups.containsKey),
      if (groups.containsKey(null)) null,
    ];

    final items = <Widget>[];
    for (final key in orderedKeys) {
      final bucket = groups[key] ?? [];
      final label = key == null
          ? 'Uncategorised'
          : projects.where((p) => p.id == key).firstOrNull?.name ??
              'Project';

      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            letterSpacing: 0.8,
          ),
        ),
      ));

      for (var i = 0; i < bucket.length; i++) {
        final s = bucket[i];
        items.add(_ThreadTile(
          session: s,
          onTap: () => onTap(s),
          onLongPress: () => onLongPress(s),
        ));
        if (i < bucket.length - 1) {
          items.add(const Divider(height: 1, indent: 60, endIndent: 16));
        }
      }
    }

    return ListView(children: items);
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final bool isSearching;

  const _EmptyState({required this.isSearching});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.forum_outlined,
            size: 56,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            isSearching ? 'No threads match your search' : 'No threads yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context menu bottom sheet
// ---------------------------------------------------------------------------

class _SessionContextMenu extends StatelessWidget {
  final ChatSession session;
  final List<ChatProject> projects;
  final VoidCallback onArchive;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final ValueChanged<String?> onMoveToProject;

  const _SessionContextMenu({
    required this.session,
    required this.projects,
    required this.onArchive,
    required this.onRename,
    required this.onExport,
    required this.onMoveToProject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              session.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: onRename,
          ),
          ListTile(
            leading: const Icon(Icons.file_copy_outlined),
            title: const Text('Export as markdown'),
            onTap: onExport,
          ),
          if (projects.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Move to project'),
              onTap: () => _showProjectPicker(context),
            ),
          ],
          ListTile(
            leading: Icon(Icons.archive_outlined,
                color: theme.colorScheme.error),
            title: Text('Archive',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: onArchive,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showProjectPicker(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Move to project',
                style: Theme.of(ctx).textTheme.titleSmall),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: const Text('Remove from project'),
            onTap: () {
              Navigator.pop(ctx);
              onMoveToProject(null);
            },
          ),
          ...projects.map((p) => ListTile(
                leading: Text(p.emoji ?? '📁',
                    style: const TextStyle(fontSize: 20)),
                title: Text(p.name),
                onTap: () {
                  Navigator.pop(ctx);
                  onMoveToProject(p.id);
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
