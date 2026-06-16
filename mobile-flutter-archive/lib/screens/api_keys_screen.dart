// T-1174: ApiKeysScreen — list API keys with prefix + badges, revoke,
// CreateApiKeySheet with show-once full key display.

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/api_key_provider.dart';

// ---------------------------------------------------------------------------
// ApiKeysScreen
// ---------------------------------------------------------------------------

class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(apiKeyProvider.notifier).loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(apiKeyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Keys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create key',
            onPressed: () => _showCreateSheet(context),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(child: Text('Error: ${state.error}'))
              : state.keys.isEmpty
                  ? _EmptyState(onCreate: () => _showCreateSheet(context))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.keys.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) => _KeyCard(
                        record: state.keys[i],
                        onRevoke: () => _confirmRevoke(context, state.keys[i]),
                      ),
                    ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateApiKeySheet(),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, ApiKeyRecord record) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke key?'),
        content: Text('Revoke "${record.name}" (${record.keyPrefix}...)? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final success = await ref.read(apiKeyProvider.notifier).revokeKey(record.id);
      messenger.showSnackBar(SnackBar(
        content: Text(success ? 'Key revoked.' : 'Failed to revoke key.'),
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// _KeyCard
// ---------------------------------------------------------------------------

class _KeyCard extends StatelessWidget {
  final ApiKeyRecord record;
  final VoidCallback onRevoke;

  const _KeyCard({required this.record, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(record.name,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(width: 8),
                      if (record.adminAllowed)
                        _Badge(label: 'admin', color: Colors.orange),
                      const SizedBox(width: 4),
                      _Badge(
                        label: '${record.rpmLimit} RPM',
                        color: cs.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${record.keyPrefix}...',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                  if (record.lastUsedAt != null)
                    Text(
                      'Last used ${_formatDate(record.lastUsedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: 'Revoke',
              onPressed: onRevoke,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays}d ago';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CreateApiKeySheet
// ---------------------------------------------------------------------------

class _CreateApiKeySheet extends ConsumerStatefulWidget {
  const _CreateApiKeySheet();

  @override
  ConsumerState<_CreateApiKeySheet> createState() => _CreateApiKeySheetState();
}

class _CreateApiKeySheetState extends ConsumerState<_CreateApiKeySheet> {
  final _nameCtrl = TextEditingController();
  bool _adminAllowed = false;
  int _rpmLimit = 60;
  bool _loading = false;
  String? _createdKey;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Create API Key',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (_createdKey == null) ...[
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Key name',
                hintText: 'e.g. My app',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'RPM limit',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _rpmLimit = int.tryParse(v) ?? 60,
                    controller: TextEditingController(text: '60'),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    const Text('Admin mode'),
                    Switch(
                      value: _adminAllowed,
                      onChanged: (v) => setState(() => _adminAllowed = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ] else ...[
            // Show-once key display.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha:0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      const Text('Key created — copy it now, it will not be shown again.',
                          style: TextStyle(color: Colors.green, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _createdKey!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _createdKey!));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final result = await ref.read(apiKeyProvider.notifier).createKey(
          name: _nameCtrl.text.trim(),
          adminAllowed: _adminAllowed,
          rpmLimit: _rpmLimit,
        );
    if (mounted) {
      setState(() {
        _loading = false;
        _createdKey = result?.fullKey;
      });
    }
  }
}

// ---------------------------------------------------------------------------
// _EmptyState
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vpn_key_outlined,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text('No API keys yet'),
          const SizedBox(height: 8),
          FilledButton(onPressed: onCreate, child: const Text('Create key')),
        ],
      ),
    );
  }
}
