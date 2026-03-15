// T-1144: KnowledgeSearchSheet — bottom sheet for searching the nSelf knowledge base.
//
// Features:
//   - Search field with real-time BM25 results
//   - Category filter chips (loaded from /claw/knowledge/categories)
//   - Expandable result cards showing title, snippet, commands, suggested actions
//   - Actionable command chips (copy to clipboard)
//   - Version info footer from /claw/knowledge/version
//   - Uses KnowledgeProvider (Riverpod) — T-1143

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/knowledge_provider.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Show the knowledge search sheet as a modal bottom sheet.
Future<void> showKnowledgeSearchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _KnowledgeSearchSheet(),
  );
}

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------

class _KnowledgeSearchSheet extends ConsumerStatefulWidget {
  const _KnowledgeSearchSheet();

  @override
  ConsumerState<_KnowledgeSearchSheet> createState() =>
      _KnowledgeSearchSheetState();
}

class _KnowledgeSearchSheetState extends ConsumerState<_KnowledgeSearchSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  List<String> _categories = const [];
  String? _selectedCategory;
  KnowledgeVersion? _versionInfo;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final notifier = ref.read(knowledgeProvider.notifier);
    final cats = await notifier.getCategories();
    final ver = await notifier.getVersionInfo();
    if (mounted) {
      setState(() {
        _categories = cats;
        _versionInfo = ver;
      });
    }
  }

  void _search(String query) {
    if (query.trim().isEmpty) {
      ref.read(knowledgeProvider.notifier).clearResults();
      return;
    }
    ref.read(knowledgeProvider.notifier).search(
          query.trim(),
          category: _selectedCategory,
          top: 8,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(knowledgeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.menu_book_rounded,
                      color: colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text('nSelf Knowledge',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search nSelf docs...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: state.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(knowledgeProvider.notifier)
                                    .clearResults();
                                setState(() {});
                              },
                            )
                          : null),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) {
                  setState(() {});
                  if (v.length >= 2) _search(v);
                },
                onSubmitted: _search,
                textInputAction: TextInputAction.search,
              ),
            ),

            // Category chips
            if (_categories.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _CategoryChip(
                      label: 'All',
                      selected: _selectedCategory == null,
                      onTap: () {
                        setState(() => _selectedCategory = null);
                        if (_searchController.text.isNotEmpty) {
                          _search(_searchController.text);
                        }
                      },
                    ),
                    ..._categories.map((cat) => _CategoryChip(
                          label: cat,
                          selected: _selectedCategory == cat,
                          onTap: () {
                            setState(() => _selectedCategory = cat);
                            if (_searchController.text.isNotEmpty) {
                              _search(_searchController.text);
                            }
                          },
                        )),
                  ],
                ),
              ),

            const Divider(height: 1),

            // Results
            Expanded(
              child: state.results.isEmpty && !state.isLoading
                  ? _EmptyState(
                      query: state.query,
                      error: state.error,
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: state.results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) =>
                          _ChunkCard(chunk: state.results[i]),
                    ),
            ),

            // Version info footer
            if (_versionInfo != null)
              Container(
                color: colorScheme.surfaceContainerLowest,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14,
                        color: colorScheme.onSurface.withAlpha(120)),
                    const SizedBox(width: 4),
                    Text(
                      'nSelf v${_versionInfo!.version} · '
                      '${_versionInfo!.totalChunks} articles',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurface.withAlpha(120)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category chip
// ---------------------------------------------------------------------------

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label,
            style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.primaryContainer,
        checkmarkColor: cs.primary,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chunk result card
// ---------------------------------------------------------------------------

class _ChunkCard extends StatefulWidget {
  const _ChunkCard({required this.chunk});
  final KnowledgeChunk chunk;

  @override
  State<_ChunkCard> createState() => _ChunkCardState();
}

class _ChunkCardState extends State<_ChunkCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chunk = widget.chunk;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chunk.title,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (chunk.category.isNotEmpty)
                          Text(
                            chunk.category,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.primary),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),

              // Snippet (always visible)
              const SizedBox(height: 6),
              Text(
                _expanded
                    ? chunk.content
                    : (chunk.content.length > 120
                        ? '${chunk.content.substring(0, 120)}…'
                        : chunk.content),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurface.withAlpha(180)),
              ),

              // Expanded: commands + suggested actions
              if (_expanded) ...[
                if (chunk.commands.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Commands',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurface.withAlpha(140))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: chunk.commands
                        .map((cmd) => _CommandChip(cmd: cmd))
                        .toList(),
                  ),
                ],
                if (chunk.suggestedActions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Actions',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurface.withAlpha(140))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: chunk.suggestedActions
                        .map((a) => _ActionChip(label: a))
                        .toList(),
                  ),
                ],
                if (chunk.userNotes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Notes',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurface.withAlpha(140))),
                  const SizedBox(height: 4),
                  ...chunk.userNotes.map((note) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.sticky_note_2_outlined,
                                size: 14,
                                color: cs.tertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(note,
                                  style: theme.textTheme.bodySmall),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Command chip — tap to copy
// ---------------------------------------------------------------------------

class _CommandChip extends StatelessWidget {
  const _CommandChip({required this.cmd});
  final String cmd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: cmd));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied: $cmd'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Chip(
        avatar: Icon(Icons.terminal, size: 14, color: cs.onSecondaryContainer),
        label: Text(cmd,
            style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: cs.onSecondaryContainer)),
        backgroundColor: cs.secondaryContainer,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action chip — suggested next action
// ---------------------------------------------------------------------------

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: cs.tertiaryContainer,
      labelStyle: TextStyle(color: cs.onTertiaryContainer),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: label));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied: $label'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.query, this.error});
  final String? query;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 36),
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: cs.error)),
          ],
        ),
      );
    }
    if (query != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: cs.onSurfaceVariant, size: 36),
            const SizedBox(height: 8),
            Text('No results for "$query"',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, color: cs.onSurfaceVariant, size: 40),
          const SizedBox(height: 8),
          Text('Search nSelf documentation',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('CLI commands, plugins, architecture...',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withAlpha(120))),
        ],
      ),
    );
  }
}
