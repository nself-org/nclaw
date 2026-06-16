// T-1106: ProjectListScreen — project management with CRUD operations.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_provider.dart';
import 'thread_list_screen.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// 8 colour presets for projects.
const _presetColors = <Color>[
  Color(0xFF0EA5E9), // sky-500 — nSelf brand
  Color(0xFF3B82F6), // blue
  Color(0xFF22C55E), // green
  Color(0xFFEF4444), // red
  Color(0xFFF97316), // orange
  Color(0xFFEAB308), // yellow
  Color(0xFFA855F7), // purple
  Color(0xFF06B6D4), // cyan
];

/// Hex strings matching [_presetColors] in the same order.
const _presetColorHexStrings = <String>[
  '#0EA5E9', '#3B82F6', '#22C55E', '#EF4444',
  '#F97316', '#EAB308', '#A855F7', '#06B6D4',
];

/// Emoji palette shown in the icon picker.
const _emojis = <String>[
  '📁', '📂', '🗂️', '📋', '📊', '📈', '🚀', '🌟',
  '💡', '🔥', '⚡', '🛠️', '🔧', '💻', '📱', '🤖',
  '🌐', '🏠', '🏢', '🎯', '🎨', '📝', '📌', '🔑',
  '💼', '🧠', '🧪', '🌱', '🌊', '🎵', '🏆', '✅',
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _parseProjectColor(String? hex) {
  if (hex == null || hex.isEmpty) return const Color(0xFF0EA5E9);
  try {
    return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
  } catch (_) {
    return const Color(0xFF0EA5E9);
  }
}

String _hexColor(Color c) {
  final idx = _presetColors.indexOf(c);
  return idx >= 0 ? _presetColorHexStrings[idx] : '#0EA5E9';
}

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

/// Browse and manage chat projects.
///
/// Features:
/// - Project cards: colour swatch, emoji icon, name, thread count, last
///   activity
/// - Add project: bottom sheet with name, emoji picker, 8 colour presets,
///   optional system prompt
/// - Long press: Rename · Change colour/emoji · Archive
/// - Tap → [ThreadListScreen] filtered by that project
/// - Pull-to-refresh
class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final projects = chatState.projects;
    final sessions = chatState.sessions;

    // Compute per-project thread count and most-recent session date.
    final threadCounts = <String, int>{};
    final lastActivity = <String, DateTime>{};
    for (final s in sessions) {
      final pid = s.projectId;
      if (pid == null) continue;
      threadCounts[pid] = (threadCounts[pid] ?? 0) + 1;
      final existing = lastActivity[pid];
      if (existing == null || s.createdAt.isAfter(existing)) {
        lastActivity[pid] = s.createdAt;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context, ref),
        tooltip: 'New project',
        child: const Icon(Icons.add),
      ),
      body: projects.isEmpty
          ? _EmptyState(onAdd: () => _showAddSheet(context, ref))
          : RefreshIndicator(
              onRefresh: () => ref.read(chatProvider.notifier).loadProjects(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                itemCount: projects.length,
                itemBuilder: (_, index) {
                  final p = projects[index];
                  return _ProjectCard(
                    project: p,
                    threadCount: threadCounts[p.id] ?? 0,
                    lastActivity: lastActivity[p.id],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ThreadListScreen(filterProjectId: p.id),
                      ),
                    ),
                    onLongPress: () => _showContextMenu(context, ref, p),
                  );
                },
              ),
            ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProjectFormSheet(
        onSubmit: ({
          required name,
          required color,
          required emoji,
          systemPrompt,
        }) {
          ref.read(chatProvider.notifier).createProject(
                name,
                color: color,
                emoji: emoji,
                systemPrompt: systemPrompt,
              );
        },
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, WidgetRef ref, ChatProject project) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () {
              Navigator.of(ctx).pop();
              _showRenameDialog(context, ref, project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Change colour & emoji'),
            onTap: () {
              Navigator.of(ctx).pop();
              _showEditSheet(context, ref, project);
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archive'),
            onTap: () {
              Navigator.of(ctx).pop();
              ref.read(chatProvider.notifier).archiveProject(project.id);
            },
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, ChatProject project) {
    final ctrl = TextEditingController(text: project.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Project name'),
          onSubmitted: (_) {
            final name = ctrl.text.trim();
            if (name.isNotEmpty) {
              ref.read(chatProvider.notifier).renameProject(project.id, name);
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(chatProvider.notifier)
                    .renameProject(project.id, name);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, ChatProject project) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProjectFormSheet(
        initial: project,
        onSubmit: ({
          required name,
          required color,
          required emoji,
          systemPrompt,
        }) {
          final notifier = ref.read(chatProvider.notifier);
          if (name != project.name) notifier.renameProject(project.id, name);
          if (color != project.color) {
            notifier.changeProjectColor(project.id, color);
          }
          if (emoji != project.emoji) {
            notifier.changeProjectEmoji(project.id, emoji);
          }
          if (systemPrompt != null &&
              systemPrompt != (project.systemPrompt ?? '')) {
            notifier.updateProjectSystemPrompt(project.id, systemPrompt);
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Project card
// ---------------------------------------------------------------------------

class _ProjectCard extends StatelessWidget {
  final ChatProject project;
  final int threadCount;
  final DateTime? lastActivity;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ProjectCard({
    required this.project,
    required this.threadCount,
    required this.lastActivity,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _parseProjectColor(project.color);
    final emoji = project.emoji ?? '📁';

    final activityText = lastActivity != null
        ? ' · ${_relativeTime(lastActivity!)}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Colour swatch — left border
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Emoji icon
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 14),
                // Name + stats
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$threadCount thread${threadCount == 1 ? '' : 's'}'
                          '$activityText',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit project bottom sheet
// ---------------------------------------------------------------------------

typedef _ProjectFormCallback = void Function({
  required String name,
  required String color,
  required String emoji,
  String? systemPrompt,
});

class _ProjectFormSheet extends StatefulWidget {
  final ChatProject? initial;
  final _ProjectFormCallback onSubmit;

  const _ProjectFormSheet({this.initial, required this.onSubmit});

  @override
  State<_ProjectFormSheet> createState() => _ProjectFormSheetState();
}

class _ProjectFormSheetState extends State<_ProjectFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _promptCtrl;
  late Color _selectedColor;
  late String _selectedEmoji;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _promptCtrl =
        TextEditingController(text: widget.initial?.systemPrompt ?? '');
    _selectedColor = _parseProjectColor(widget.initial?.color);
    _selectedEmoji = widget.initial?.emoji ?? '📁';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.initial != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet header
            Row(
              children: [
                Text(
                  isEdit ? 'Edit project' : 'New project',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Name field
            TextField(
              controller: _nameCtrl,
              autofocus: !isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Project name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Emoji picker
            Text('Icon', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            _EmojiPicker(
              selected: _selectedEmoji,
              onSelect: (e) => setState(() => _selectedEmoji = e),
            ),
            const SizedBox(height: 20),

            // Colour picker
            Text('Colour', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            _ColorPicker(
              selected: _selectedColor,
              onSelect: (c) => setState(() => _selectedColor = c),
            ),
            const SizedBox(height: 20),

            // System prompt (optional)
            TextField(
              controller: _promptCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'System prompt (optional)',
                hintText: "Instructions applied to all sessions in this project",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  widget.onSubmit(
                    name: name,
                    color: _hexColor(_selectedColor),
                    emoji: _selectedEmoji,
                    systemPrompt: _promptCtrl.text.trim().isEmpty
                        ? null
                        : _promptCtrl.text.trim(),
                  );
                  Navigator.of(context).pop();
                },
                child: Text(isEdit ? 'Save changes' : 'Create project'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji picker widget
// ---------------------------------------------------------------------------

class _EmojiPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _EmojiPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _emojis.map((e) {
        final isSelected = e == selected;
        return GestureDetector(
          onTap: () => onSelect(e),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(e, style: const TextStyle(fontSize: 20)),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Colour picker widget
// ---------------------------------------------------------------------------

class _ColorPicker extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onSelect;

  const _ColorPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _presetColors.map((c) {
        final isSelected = c == selected;
        return GestureDetector(
          onTap: () => onSelect(c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 2.5,
                    )
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: c.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No projects yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Group your threads into projects',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New project'),
          ),
        ],
      ),
    );
  }
}
