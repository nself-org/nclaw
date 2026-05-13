// T-1147: KnowledgeSettingsCard — settings card for knowledge base configuration.
//
// Features:
//   - Version info + total chunk count
//   - Toggle: inject knowledge context into responses
//   - Toggle: nSelf expert mode (prepends NSELF_EXPERT_PREAMBLE)
//   - Toggle: show knowledge badge on chat messages
//   - Note count + clear notes option
//   - Uses KnowledgeProvider (Riverpod) — T-1143

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/knowledge_provider.dart';
import '../providers/connection_provider.dart';

// ---------------------------------------------------------------------------
// Shared preferences keys (used when wiring up shared_preferences)
// ---------------------------------------------------------------------------

// ignore: unused_element
const _kInjectKnowledge = 'knowledge_inject';
// ignore: unused_element
const _kExpertMode = 'knowledge_expert_mode';
// ignore: unused_element
const _kShowBadge = 'knowledge_show_badge';

// ---------------------------------------------------------------------------
// Local prefs provider (simple in-memory for now; swap for shared_preferences)
// ---------------------------------------------------------------------------

final _knowledgePrefsProvider =
    StateNotifierProvider<_KnowledgePrefsNotifier, _KnowledgePrefs>(
  (_) => _KnowledgePrefsNotifier(),
);

class _KnowledgePrefs {
  final bool injectKnowledge;
  final bool expertMode;
  final bool showBadge;

  const _KnowledgePrefs({
    this.injectKnowledge = true,
    this.expertMode = false,
    this.showBadge = true,
  });

  _KnowledgePrefs copyWith({
    bool? injectKnowledge,
    bool? expertMode,
    bool? showBadge,
  }) =>
      _KnowledgePrefs(
        injectKnowledge: injectKnowledge ?? this.injectKnowledge,
        expertMode: expertMode ?? this.expertMode,
        showBadge: showBadge ?? this.showBadge,
      );
}

class _KnowledgePrefsNotifier extends StateNotifier<_KnowledgePrefs> {
  _KnowledgePrefsNotifier() : super(const _KnowledgePrefs());

  void setInjectKnowledge(bool v) =>
      state = state.copyWith(injectKnowledge: v);
  void setExpertMode(bool v) => state = state.copyWith(expertMode: v);
  void setShowBadge(bool v) => state = state.copyWith(showBadge: v);
}

// ---------------------------------------------------------------------------
// Card widget
// ---------------------------------------------------------------------------

class KnowledgeSettingsCard extends ConsumerStatefulWidget {
  const KnowledgeSettingsCard({super.key});

  @override
  ConsumerState<KnowledgeSettingsCard> createState() =>
      _KnowledgeSettingsCardState();
}

class _KnowledgeSettingsCardState
    extends ConsumerState<KnowledgeSettingsCard> {
  KnowledgeVersion? _version;
  int _noteCount = 0;
  bool _loadingMeta = true;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final conn = ref.read(connectionProvider);
    if (conn.activeServer == null) {
      if (mounted) setState(() => _loadingMeta = false);
      return;
    }
    final notifier = ref.read(knowledgeProvider.notifier);
    final ver = await notifier.getVersionInfo();
    final notes = await notifier.getNotes();
    if (mounted) {
      setState(() {
        _version = ver;
        _noteCount = notes.length;
        _loadingMeta = false;
      });
    }
  }

  Future<void> _confirmClearNotes(BuildContext context) async {
    // Capture messenger before any async gap.
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notes?'),
        content: Text('This will delete all $_noteCount operator notes '
            'attached to knowledge chunks. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final notes =
        await ref.read(knowledgeProvider.notifier).getNotes();
    int deleted = 0;
    for (final note in notes) {
      final ok =
          await ref.read(knowledgeProvider.notifier).deleteNote(note.id);
      if (ok) deleted++;
    }
    if (mounted) {
      setState(() => _noteCount = 0);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted $deleted notes'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(_knowledgePrefsProvider);
    final prefsNotifier = ref.read(_knowledgePrefsProvider.notifier);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('Knowledge Base',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_loadingMeta)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.primary),
                  )
                else if (_version != null)
                  Text(
                    'v${_version!.version} · ${_version!.totalChunks} articles',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurface.withAlpha(140)),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Inject toggle
          SwitchListTile(
            dense: true,
            title: const Text('Inject knowledge context'),
            subtitle: const Text(
                'Include relevant docs in responses automatically'),
            value: prefs.injectKnowledge,
            onChanged: prefsNotifier.setInjectKnowledge,
          ),

          // Expert mode toggle
          SwitchListTile(
            dense: true,
            title: const Text('ɳSelf expert mode'),
            subtitle: const Text(
                'Prepend an ɳSelf-expert system prompt to every message'),
            value: prefs.expertMode,
            onChanged:
                prefs.injectKnowledge ? prefsNotifier.setExpertMode : null,
          ),

          // Badge toggle
          SwitchListTile(
            dense: true,
            title: const Text('Show "docs used" badge'),
            subtitle: const Text(
                'Display a badge on messages backed by knowledge'),
            value: prefs.showBadge,
            onChanged: prefsNotifier.setShowBadge,
          ),

          // Note count + clear
          if (_noteCount > 0) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.sticky_note_2_outlined,
                  size: 20, color: cs.tertiary),
              title: Text('$_noteCount operator note${_noteCount == 1 ? '' : 's'}'),
              subtitle: const Text('Custom annotations on knowledge chunks'),
              trailing: TextButton(
                onPressed: () => _confirmClearNotes(context),
                child: const Text('Clear all'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
