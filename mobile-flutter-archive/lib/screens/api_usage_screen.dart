// T-1175: API Usage Screen — per-key usage stats with day/model breakdown.
// Reads from /claw/v1/usage via ApiKeyProvider.

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/api_key_provider.dart';

class ApiUsageScreen extends ConsumerStatefulWidget {
  const ApiUsageScreen({super.key});

  @override
  ConsumerState<ApiUsageScreen> createState() => _ApiUsageScreenState();
}

class _ApiUsageScreenState extends ConsumerState<ApiUsageScreen> {
  String? _selectedKeyId;

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
    final cs = Theme.of(context).colorScheme;

    // Filter usage rows by selected key.
    final rows = _selectedKeyId == null
        ? state.usage
        : state.usage.where((r) => r.keyId == _selectedKeyId).toList();

    // Aggregate by day.
    final Map<String, int> byDay = {};
    for (final r in rows) {
      byDay[r.day] = (byDay[r.day] ?? 0) + r.totalTokens;
    }
    final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // Aggregate by model.
    final Map<String, int> byModel = {};
    for (final r in rows) {
      byModel[r.model] = (byModel[r.model] ?? 0) + r.totalTokens;
    }

    final totalTokens = rows.fold<int>(0, (s, r) => s + r.totalTokens);
    final totalCost = rows.fold<double>(0, (s, r) => s + r.costUsd);

    return Scaffold(
      appBar: AppBar(title: const Text('API Usage')),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.usage.isEmpty
              ? const Center(child: Text('No usage recorded yet.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Key filter.
                    if (state.keys.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedKeyId,
                        decoration: const InputDecoration(
                          labelText: 'Filter by key',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All keys')),
                          ...state.keys.map((k) => DropdownMenuItem(
                                value: k.id,
                                child: Text('${k.name} (${k.keyPrefix}...)'),
                              )),
                        ],
                        onChanged: (v) => setState(() => _selectedKeyId = v),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Totals summary.
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Total tokens',
                            value: _formatNum(totalTokens),
                            icon: Icons.data_usage,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'Est. cost',
                            value: '\$${totalCost.toStringAsFixed(4)}',
                            icon: Icons.attach_money,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // By model breakdown.
                    if (byModel.isNotEmpty) ...[
                      Text('By model', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...byModel.entries.map((e) => _BarRow(
                            label: e.key,
                            value: e.value,
                            max: byModel.values.reduce((a, b) => a > b ? a : b),
                            color: cs.primary,
                          )),
                      const SizedBox(height: 20),
                    ],

                    // By day breakdown.
                    if (sortedDays.isNotEmpty) ...[
                      Text('By day', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...sortedDays.take(14).map((day) => _BarRow(
                            label: day,
                            value: byDay[day]!,
                            max: byDay.values.reduce((a, b) => a > b ? a : b),
                            color: cs.secondary,
                          )),
                    ],
                  ],
                ),
    );
  }

  String _formatNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

// ---------------------------------------------------------------------------
// _StatCard
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(height: 8),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BarRow — horizontal bar chart row
// ---------------------------------------------------------------------------

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;

  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = max > 0 ? value / max : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              value.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
