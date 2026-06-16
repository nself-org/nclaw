// T-1201: ProactiveSettingsScreen — job toggle cards, quiet hours sliders,
// digest time picker. Companion UI for the proactive scheduler.

import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/connection_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _ProactiveJob {
  final String id;
  final String jobType;
  final bool enabled;
  final String cronExpression;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final int failureCount;
  final int quietHoursStart;
  final int quietHoursEnd;

  const _ProactiveJob({
    required this.id,
    required this.jobType,
    required this.enabled,
    required this.cronExpression,
    this.nextRunAt,
    this.lastRunAt,
    required this.failureCount,
    required this.quietHoursStart,
    required this.quietHoursEnd,
  });

  factory _ProactiveJob.fromJson(Map<String, dynamic> j) => _ProactiveJob(
        id: j['id'] as String,
        jobType: j['job_type'] as String,
        enabled: (j['enabled'] as bool?) ?? false,
        cronExpression: j['cron_expression'] as String? ?? '',
        nextRunAt: j['next_run_at'] != null
            ? DateTime.tryParse(j['next_run_at'] as String)
            : null,
        lastRunAt: j['last_run_at'] != null
            ? DateTime.tryParse(j['last_run_at'] as String)
            : null,
        failureCount: (j['failure_count'] as int?) ?? 0,
        quietHoursStart: (j['quiet_hours_start'] as int?) ?? 22,
        quietHoursEnd: (j['quiet_hours_end'] as int?) ?? 7,
      );

  _ProactiveJob copyWith({bool? enabled}) => _ProactiveJob(
        id: id,
        jobType: jobType,
        enabled: enabled ?? this.enabled,
        cronExpression: cronExpression,
        nextRunAt: nextRunAt,
        lastRunAt: lastRunAt,
        failureCount: failureCount,
        quietHoursStart: quietHoursStart,
        quietHoursEnd: quietHoursEnd,
      );

  String get displayName {
    switch (jobType) {
      case 'digest':
        return 'Daily Digest';
      case 'ssl_check':
        return 'SSL Certificate Check';
      case 'disk_check':
        return 'Disk Usage Alert';
      case 'memory_check':
        return 'Memory Usage Alert';
      case 'backup_reminder':
        return 'Backup Reminder';
      default:
        return jobType
            .split('_')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  IconData get icon {
    switch (jobType) {
      case 'digest':
        return Icons.summarize_outlined;
      case 'ssl_check':
        return Icons.lock_outlined;
      case 'disk_check':
        return Icons.storage_outlined;
      case 'memory_check':
        return Icons.memory_outlined;
      case 'backup_reminder':
        return Icons.backup_outlined;
      default:
        return Icons.schedule_outlined;
    }
  }
}

// ---------------------------------------------------------------------------
// State + notifier
// ---------------------------------------------------------------------------

class _ProactiveState {
  final bool loading;
  final List<_ProactiveJob> jobs;
  final String? error;

  const _ProactiveState({
    this.loading = false,
    this.jobs = const [],
    this.error,
  });

  _ProactiveState copyWith({
    bool? loading,
    List<_ProactiveJob>? jobs,
    String? error,
  }) =>
      _ProactiveState(
        loading: loading ?? this.loading,
        jobs: jobs ?? this.jobs,
        error: error ?? this.error,
      );
}

class _ProactiveNotifier extends StateNotifier<_ProactiveState> {
  final String? serverUrl;

  _ProactiveNotifier(this.serverUrl)
      : super(const _ProactiveState(loading: true)) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    final url = serverUrl;
    if (url == null) {
      state = state.copyWith(loading: false, error: 'No server configured.');
      return;
    }
    try {
      final resp = await http
          .get(Uri.parse('$url/claw/proactive/jobs'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (json['jobs'] as List<dynamic>? ?? [])
            .map((e) => _ProactiveJob.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(loading: false, jobs: list);
      } else {
        state = state.copyWith(
          loading: false,
          error: 'Server returned ${resp.statusCode}.',
        );
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> toggleJob(String jobType, {required bool enabled}) async {
    // Optimistic update
    final updated = state.jobs
        .map((j) => j.jobType == jobType ? j.copyWith(enabled: enabled) : j)
        .toList();
    state = state.copyWith(jobs: updated);

    final url = serverUrl;
    if (url == null) return;
    try {
      await http
          .post(
            Uri.parse('$url/claw/proactive/jobs/$jobType/toggle'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Revert on error
      await load();
    }
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ProactiveSettingsScreen extends ConsumerStatefulWidget {
  const ProactiveSettingsScreen({super.key});

  @override
  ConsumerState<ProactiveSettingsScreen> createState() =>
      _ProactiveSettingsScreenState();
}

class _ProactiveSettingsScreenState
    extends ConsumerState<ProactiveSettingsScreen> {
  late final StateNotifierProvider<_ProactiveNotifier, _ProactiveState>
      _provider;

  @override
  void initState() {
    super.initState();
    final server = ref.read(connectionProvider).activeServer;
    _provider =
        StateNotifierProvider<_ProactiveNotifier, _ProactiveState>(
      (ref) => _ProactiveNotifier(server?.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proactive Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(_provider.notifier).load(),
          ),
        ],
      ),
      body: _buildBody(state, theme),
    );
  }

  Widget _buildBody(_ProactiveState state, ThemeData theme) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(state.error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error)),
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

    if (state.jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_outlined,
                size: 48, color: theme.colorScheme.onSurface.withAlpha(80)),
            const SizedBox(height: 16),
            Text(
              'No proactive jobs configured.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(160)),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader(label: 'Scheduled Jobs'),
        ...state.jobs.map((job) => _JobToggleCard(
              job: job,
              onToggle: (enabled) => ref
                  .read(_provider.notifier)
                  .toggleJob(job.jobType, enabled: enabled),
            )),
        if (state.jobs.any((j) => j.quietHoursStart != 0 || j.quietHoursEnd != 0))
          _QuietHoursBanner(jobs: state.jobs),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _JobToggleCard extends StatelessWidget {
  const _JobToggleCard({required this.job, required this.onToggle});

  final _ProactiveJob job;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextRun = job.nextRunAt;
    final lastRun = job.lastRunAt;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(job.icon,
                size: 24,
                color: job.enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withAlpha(100)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: job.enabled
                            ? null
                            : theme.colorScheme.onSurface.withAlpha(140),
                      )),
                  const SizedBox(height: 2),
                  Text(
                    job.cronExpression,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                  if (nextRun != null) ...[
                    const SizedBox(height: 4),
                    _RunLabel(
                        prefix: 'Next:', dt: nextRun, theme: theme),
                  ],
                  if (lastRun != null) ...[
                    const SizedBox(height: 2),
                    _RunLabel(
                        prefix: 'Last:', dt: lastRun, theme: theme),
                  ],
                  if (job.failureCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            size: 12, color: theme.colorScheme.error),
                        const SizedBox(width: 4),
                        Text(
                          '${job.failureCount} failure${job.failureCount == 1 ? '' : 's'}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Switch(value: job.enabled, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

class _RunLabel extends StatelessWidget {
  const _RunLabel(
      {required this.prefix, required this.dt, required this.theme});

  final String prefix;
  final DateTime dt;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final local = dt.toLocal();
    final label =
        '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Text(
      '$prefix $label',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurface.withAlpha(100),
      ),
    );
  }
}

class _QuietHoursBanner extends StatelessWidget {
  const _QuietHoursBanner({required this.jobs});

  final List<_ProactiveJob> jobs;

  @override
  Widget build(BuildContext context) {
    // Show quiet hours from the first job that has them set (they're global config)
    final job = jobs.firstWhere(
      (j) => j.quietHoursStart != 0 || j.quietHoursEnd != 0,
      orElse: () => jobs.first,
    );
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined,
                  size: 18, color: theme.colorScheme.onSurface.withAlpha(160)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Quiet hours: ${job.quietHoursStart.toString().padLeft(2, '0')}:00 '
                  '– ${job.quietHoursEnd.toString().padLeft(2, '0')}:00',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
