import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/connection_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _UsageSummary {
  final int totalRequests;
  final int cacheHits;
  final double savingsUsd;
  final Map<String, int> tiers; // local, free_gemini, api_key
  final List<_ProviderRow> providers;

  const _UsageSummary({
    required this.totalRequests,
    required this.cacheHits,
    required this.savingsUsd,
    required this.tiers,
    required this.providers,
  });

  factory _UsageSummary.fromJson(Map<String, dynamic> json) {
    final tiersRaw = json['tiers'];
    final Map<String, int> tiers = {};
    if (tiersRaw is Map) {
      tiersRaw.forEach((k, v) {
        tiers[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    final providersRaw = json['providers'];
    final List<_ProviderRow> providers = [];
    if (providersRaw is List) {
      for (final item in providersRaw) {
        if (item is Map<String, dynamic>) {
          providers.add(_ProviderRow.fromJson(item));
        }
      }
    }

    return _UsageSummary(
      totalRequests: (json['total_requests'] as num?)?.toInt() ?? 0,
      cacheHits: (json['cache_hits'] as num?)?.toInt() ?? 0,
      savingsUsd: (json['savings_usd'] as num?)?.toDouble() ?? 0.0,
      tiers: tiers,
      providers: providers,
    );
  }
}

class _ProviderRow {
  final String provider;
  final int requests;
  final int tokens;

  const _ProviderRow({
    required this.provider,
    required this.requests,
    required this.tokens,
  });

  factory _ProviderRow.fromJson(Map<String, dynamic> json) {
    return _ProviderRow(
      provider: json['provider'] as String? ?? 'unknown',
      requests: (json['requests'] as num?)?.toInt() ?? 0,
      tokens: (json['tokens'] as num?)?.toInt() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider state
// ---------------------------------------------------------------------------

enum _Period { today, week, month }

extension _PeriodLabel on _Period {
  String get label {
    return switch (this) {
      _Period.today => 'Today',
      _Period.week => 'Week',
      _Period.month => 'Month',
    };
  }

  String get queryParam {
    return switch (this) {
      _Period.today => 'today',
      _Period.week => 'week',
      _Period.month => 'month',
    };
  }
}

class _UsageState {
  final _Period period;
  final bool loading;
  final _UsageSummary? data;
  final String? error;

  const _UsageState({
    this.period = _Period.today,
    this.loading = false,
    this.data,
    this.error,
  });

  _UsageState copyWith({
    _Period? period,
    bool? loading,
    _UsageSummary? data,
    String? error,
    bool clearData = false,
    bool clearError = false,
  }) {
    return _UsageState(
      period: period ?? this.period,
      loading: loading ?? this.loading,
      data: clearData ? null : (data ?? this.data),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class _UsageNotifier extends StateNotifier<_UsageState> {
  final String? serverUrl;

  _UsageNotifier(this.serverUrl) : super(const _UsageState()) {
    load();
  }

  Future<void> load({_Period? period}) async {
    final p = period ?? state.period;
    state = state.copyWith(period: p, loading: true, clearError: true);

    final url = serverUrl;
    if (url == null || url.isEmpty) {
      state = state.copyWith(loading: false, error: 'Not connected');
      return;
    }

    try {
      final uri = Uri.parse('$url/ai/usage/summary')
          .replace(queryParameters: {'period': p.queryParam});
      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        state = state.copyWith(
            loading: false, data: _UsageSummary.fromJson(json));
      } else {
        state = state.copyWith(
            loading: false,
            error: 'Server returned ${response.statusCode}');
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Failed to load: $e');
    }
  }

  void setPeriod(_Period period) => load(period: period);
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Usage dashboard screen.
///
/// Shows AI request statistics for the selected period (today / week / month).
class UsageScreen extends ConsumerStatefulWidget {
  const UsageScreen({super.key});

  @override
  ConsumerState<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends ConsumerState<UsageScreen> {
  late final StateNotifierProvider<_UsageNotifier, _UsageState>
      _usageProvider;

  @override
  void initState() {
    super.initState();
    final serverUrl = ref.read(connectionProvider).activeServer?.url;
    _usageProvider =
        StateNotifierProvider<_UsageNotifier, _UsageState>((ref) {
      return _UsageNotifier(serverUrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final usageState = ref.watch(_usageProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(_usageProvider.notifier).load(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Period selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<_Period>(
              segments: _Period.values
                  .map((p) => ButtonSegment<_Period>(
                        value: p,
                        label: Text(p.label),
                      ))
                  .toList(),
              selected: {usageState.period},
              onSelectionChanged: (selection) {
                ref
                    .read(_usageProvider.notifier)
                    .setPeriod(selection.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildBody(context, theme, usageState),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, ThemeData theme, _UsageState state) {
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
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final data = state.data;
    if (data == null) {
      return Center(
        child: Text(
          'No usage data',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Summary cards
        _buildSummaryCards(theme, data),
        const SizedBox(height: 20),
        // Tier breakdown
        _buildTierBreakdown(theme, data),
        const SizedBox(height: 20),
        // Provider table
        _buildProviderTable(theme, data),
      ],
    );
  }

  Widget _buildSummaryCards(ThemeData theme, _UsageSummary data) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Total Requests',
            value: '${data.totalRequests}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: 'Cache Hits',
            value: '${data.cacheHits}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: 'Est. Savings',
            value: '\$${data.savingsUsd.toStringAsFixed(2)}',
            valueColor: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildTierBreakdown(ThemeData theme, _UsageSummary data) {
    final totalTier = data.tiers.values.fold(0, (a, b) => a + b);
    if (totalTier == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tier breakdown',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _TierBar(
              label: 'Local',
              count: data.tiers['local'] ?? 0,
              total: totalTier,
              color: Colors.green,
            ),
            const SizedBox(height: 8),
            _TierBar(
              label: 'Free Gemini',
              count: data.tiers['free_gemini'] ?? 0,
              total: totalTier,
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            _TierBar(
              label: 'API Key',
              count: data.tiers['api_key'] ?? 0,
              total: totalTier,
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderTable(ThemeData theme, _UsageSummary data) {
    if (data.providers.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('By provider', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            // Header row
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Provider',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Requests',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Tokens',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            ...data.providers.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.provider,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${row.requests}',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _formatTokens(row.tokens),
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    }
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return '$tokens';
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryCard({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _TierBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total > 0 ? count / total : 0.0;
    final pct = (fraction * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodySmall),
            ),
            Text(
              '$pct%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor:
                color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
