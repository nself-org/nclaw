// T-1199: MemoriesScreen — grouped by entity_type, confidence bar,
// times_reinforced, swipe-delete, add explicit memory FAB, filter chips.

import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/connection_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _MemoryRecord {
  final String id;
  final String entityId;
  final String entityType;
  final String content;
  final double confidence;
  final int timesReinforced;
  final String source;
  final DateTime createdAt;

  const _MemoryRecord({
    required this.id,
    required this.entityId,
    required this.entityType,
    required this.content,
    required this.confidence,
    required this.timesReinforced,
    required this.source,
    required this.createdAt,
  });

  factory _MemoryRecord.fromJson(Map<String, dynamic> json) {
    return _MemoryRecord(
      id: json['id'] as String? ?? '',
      entityId: json['entity_id'] as String? ?? '',
      entityType: json['entity_type'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      timesReinforced: (json['times_reinforced'] as num?)?.toInt() ?? 1,
      source: json['source'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider state
// ---------------------------------------------------------------------------

class _MemoriesState {
  final bool loading;
  final List<_MemoryRecord> memories;
  final String? error;
  final String? filterType; // null = all

  const _MemoriesState({
    this.loading = false,
    this.memories = const [],
    this.error,
    this.filterType,
  });

  _MemoriesState copyWith({
    bool? loading,
    List<_MemoryRecord>? memories,
    String? error,
    String? filterType,
    bool clearError = false,
    bool clearFilter = false,
  }) {
    return _MemoriesState(
      loading: loading ?? this.loading,
      memories: memories ?? this.memories,
      error: clearError ? null : (error ?? this.error),
      filterType: clearFilter ? null : (filterType ?? this.filterType),
    );
  }

  List<_MemoryRecord> get filtered {
    if (filterType == null) return memories;
    return memories.where((m) => m.entityType == filterType).toList();
  }

  Map<String, List<_MemoryRecord>> get groupedByType {
    final result = <String, List<_MemoryRecord>>{};
    for (final m in filtered) {
      result.putIfAbsent(m.entityType, () => []).add(m);
    }
    return result;
  }

  Set<String> get entityTypes {
    return memories.map((m) => m.entityType).toSet();
  }
}

class _MemoriesNotifier extends StateNotifier<_MemoriesState> {
  final String? serverUrl;
  final String? userId;

  _MemoriesNotifier(this.serverUrl, this.userId)
      : super(const _MemoriesState()) {
    load();
  }

  Future<void> load() async {
    final url = serverUrl;
    final uid = userId;
    if (url == null || uid == null || uid.isEmpty) {
      state = state.copyWith(
        loading: false,
        error: 'Not connected',
        clearError: false,
      );
      return;
    }

    state = state.copyWith(loading: true, clearError: true);
    try {
      final uri =
          Uri.parse('$url/claw/memories').replace(queryParameters: {'user_id': uid});
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (json['memories'] as List?)
                ?.map((e) => _MemoryRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        state = state.copyWith(loading: false, memories: list);
      } else {
        state = state.copyWith(
          loading: false,
          error: 'Server error ${resp.statusCode}',
        );
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Failed to load: $e');
    }
  }

  Future<bool> deleteMemory(String id) async {
    final url = serverUrl;
    if (url == null) return false;
    try {
      final uri = Uri.parse('$url/claw/memories/$id');
      final resp = await http.delete(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 204 || resp.statusCode == 200) {
        state = state.copyWith(
          memories: state.memories.where((m) => m.id != id).toList(),
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> addMemory(String content) async {
    final url = serverUrl;
    final uid = userId;
    if (url == null || uid == null || uid.isEmpty) return false;
    try {
      final uri = Uri.parse('$url/claw/memories');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': uid, 'content': content}),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final newMemory = _MemoryRecord.fromJson(json);
        state = state.copyWith(memories: [newMemory, ...state.memories]);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> clearAll() async {
    final url = serverUrl;
    final uid = userId;
    if (url == null || uid == null || uid.isEmpty) return false;
    try {
      final uri = Uri.parse('$url/claw/memories')
          .replace(queryParameters: {'user_id': uid});
      final resp = await http
          .delete(uri)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        state = state.copyWith(memories: []);
        return true;
      }
    } catch (_) {}
    return false;
  }

  void setFilter(String? type) {
    if (type == null) {
      state = state.copyWith(clearFilter: true);
    } else {
      state = state.copyWith(filterType: type);
    }
  }
}

// ---------------------------------------------------------------------------
// Helper: extract user_id from JWT (same logic as NotificationPermissionService)
// ---------------------------------------------------------------------------

String? _userIdFromJwt(String? jwt) {
  if (jwt == null || jwt.isEmpty) return null;
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    final payload = parts[1];
    final padded = payload.padRight(
      payload.length + (4 - payload.length % 4) % 4,
      '=',
    );
    final decoded = utf8.decode(base64Url.decode(padded));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    return map['sub'] as String? ?? map['user_id'] as String?;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Manages memories: grouped by entity_type, swipe-delete, add via FAB.
class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  late final StateNotifierProvider<_MemoriesNotifier, _MemoriesState>
      _provider;

  @override
  void initState() {
    super.initState();
    final server = ref.read(connectionProvider).activeServer;
    final userId = _userIdFromJwt(server?.jwtToken);
    _provider = StateNotifierProvider<_MemoriesNotifier, _MemoriesState>(
      (ref) => _MemoriesNotifier(server?.url, userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(_provider.notifier).load(),
          ),
          if (state.memories.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear_all') _confirmClearAll(context);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Clear all'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (state.entityTypes.length > 1)
            _FilterChips(
              types: state.entityTypes,
              selected: state.filterType,
              onSelected: (t) => ref.read(_provider.notifier).setFilter(t),
            ),
          Expanded(child: _buildBody(context, theme, state)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_memory_fab',
        tooltip: 'Add memory',
        onPressed: () => _showAddMemoryDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, ThemeData theme, _MemoriesState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.read(_provider.notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = state.groupedByType;
    if (grouped.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 56,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 16),
              Text(
                'No memories yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start chatting to build context.\nOr tap + to add one manually.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Build list with group headers
    final groups = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: groups.fold<int>(
          0, (sum, g) => sum + 1 + g.value.length), // header + items
      itemBuilder: (ctx, index) {
        int pos = 0;
        for (final group in groups) {
          if (index == pos) {
            return _GroupHeader(
              type: group.key,
              count: group.value.length,
            );
          }
          pos++;
          for (final mem in group.value) {
            if (index == pos) {
              return _MemoryCard(
                memory: mem,
                onDismissed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok =
                      await ref.read(_provider.notifier).deleteMemory(mem.id);
                  if (ok && mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Memory deleted'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            }
            pos++;
          }
        }
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _showAddMemoryDialog(BuildContext context) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add memory'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Enter something to remember...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (content != null && content.isNotEmpty) {
      final ok = await ref.read(_provider.notifier).addMemory(content);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? 'Memory saved' : 'Failed to save memory'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all memories?'),
        content: const Text(
            'This permanently removes all memories. ɳClaw will start fresh context.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      final cleared = await ref.read(_provider.notifier).clearAll();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(cleared ? 'All memories cleared' : 'Failed to clear'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _FilterChips extends StatelessWidget {
  final Set<String> types;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _FilterChips({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final sortedTypes = types.toList()..sort();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: 8),
          ...sortedTypes.map((type) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_typeLabel(type)),
                  selected: selected == type,
                  onSelected: (_) =>
                      onSelected(selected == type ? null : type),
                ),
              )),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    return switch (type) {
      'user' => 'User',
      'system' => 'System',
      'code' => 'Code',
      'email' => 'Email',
      'calendar' => 'Calendar',
      _ => type[0].toUpperCase() + type.substring(1),
    };
  }
}

class _GroupHeader extends StatelessWidget {
  final String type;
  final int count;

  const _GroupHeader({required this.type, required this.count});

  String get _label {
    final base = switch (type) {
      'user' => 'User',
      'system' => 'System',
      'code' => 'Code',
      'email' => 'Email',
      'calendar' => 'Calendar',
      _ => type[0].toUpperCase() + type.substring(1),
    };
    return base;
  }

  IconData get _icon {
    return switch (type) {
      'user' => Icons.person_outline,
      'system' => Icons.computer_outlined,
      'code' => Icons.code_outlined,
      'email' => Icons.email_outlined,
      'calendar' => Icons.event_outlined,
      _ => Icons.psychology_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Icon(_icon,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 6),
          Text(
            _label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final _MemoryRecord memory;
  final VoidCallback onDismissed;

  const _MemoryCard({
    required this.memory,
    required this.onDismissed,
  });

  Color _confidenceColor(double c) {
    if (c >= 0.8) return Colors.green;
    if (c >= 0.5) return Colors.amber;
    return Colors.red;
  }

  String _sourceLabel(String source) {
    return switch (source) {
      'explicit' => 'Manually added',
      'chat' => 'From chat',
      'email' => 'From email',
      'calendar' => 'From calendar',
      _ => source,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidenceColor = _confidenceColor(memory.confidence);
    final confidencePct = (memory.confidence * 100).round();

    return Dismissible(
      key: Key(memory.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => onDismissed(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memory.content,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              // Confidence bar
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Confidence',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            Text(
                              '$confidencePct%',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: confidenceColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: memory.confidence,
                            minHeight: 5,
                            backgroundColor:
                                confidenceColor.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                confidenceColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Footer row: source chip + reinforced count
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _sourceLabel(memory.source),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (memory.timesReinforced > 1) ...[
                    Icon(
                      Icons.refresh_rounded,
                      size: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${memory.timesReinforced}×',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    Icons.swipe_left_outlined,
                    size: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
