// LocalAiScreen — Local AI Settings panel for ɳClaw mobile.
// stub: FFI calls return canned data; flutter_rust_bridge codegen lands in S15.T18.
//
// Implements 4 of 7 canonical UI states: Loading, Empty, Error, Success.

import 'package:flutter/material.dart';

// --- Stub data types (will be replaced by ffb-generated types in T18) ---

enum TierLevel { t0, t1, t2, t3, t4 }

enum TierOverride { auto, t0, t1, t2, t3, t4 }

class TierInfo {
  final TierLevel active;
  final TierOverride override;
  const TierInfo({required this.active, required this.override});
}

class BenchmarkResult {
  final String date;
  final double toksPerSec;
  final String modelId;
  const BenchmarkResult({required this.date, required this.toksPerSec, required this.modelId});
}

class ModelEntry {
  final String modelId;
  final int sizeMb;
  final String? lastUsedAt;
  final List<String> roles;
  const ModelEntry({required this.modelId, required this.sizeMb, this.lastUsedAt, required this.roles});
}

// --- Stub FFI surface ---

class _LocalAiApi {
  Future<TierInfo> getTier() async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
    await Future.delayed(const Duration(milliseconds: 200));
    return const TierInfo(active: TierLevel.t2, override: TierOverride.auto);
  }

  Future<List<BenchmarkResult>> getBenchmarkHistory({int limit = 12}) async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
    return [
      const BenchmarkResult(date: '2026-05-10', toksPerSec: 42.1, modelId: 'phi-3-mini'),
      const BenchmarkResult(date: '2026-04-10', toksPerSec: 39.8, modelId: 'phi-3-mini'),
      const BenchmarkResult(date: '2026-03-10', toksPerSec: 41.3, modelId: 'phi-3-mini'),
    ].take(limit).toList();
  }

  Future<List<ModelEntry>> listModels() async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
    return const [
      ModelEntry(
        modelId: 'phi-3-mini-4k-instruct.Q4_K_M',
        sizeMb: 2340,
        lastUsedAt: '2026-05-13',
        roles: ['chat', 'summarize'],
      ),
      ModelEntry(
        modelId: 'nomic-embed-text-v1.5.Q8_0',
        sizeMb: 274,
        lastUsedAt: '2026-05-12',
        roles: ['embed'],
      ),
    ];
  }

  Future<BenchmarkResult> runBenchmark() async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
    await Future.delayed(const Duration(seconds: 1));
    return const BenchmarkResult(date: '2026-05-13', toksPerSec: 43.5, modelId: 'phi-3-mini-4k-instruct.Q4_K_M');
  }

  Future<void> setTierOverride(TierOverride? tier) async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
  }

  Future<void> setAllowT4({required bool allow}) async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
  }

  Future<void> setReBenchMonthly({required bool enabled}) async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
  }

  Future<void> deleteModel(String modelId) async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
  }

  Future<void> setModelRole(String modelId, String role) async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
  }

  Future<String?> importCustomGguf() async {
    // stub: returns canned data; backend wiring lands in S15.T18 acceptance gate
    return 'custom-model.Q4_K_M';
  }
}

// --- Screen ---

class LocalAiScreen extends StatefulWidget {
  const LocalAiScreen({super.key});

  @override
  State<LocalAiScreen> createState() => _LocalAiScreenState();
}

class _LocalAiScreenState extends State<LocalAiScreen> {
  final _api = _LocalAiApi();

  bool _loading = true;
  String? _error;

  TierInfo? _tier;
  List<BenchmarkResult> _benchmarks = [];
  List<ModelEntry> _models = [];

  bool _allowT4 = false;
  bool _reBenchMonthly = true;
  bool _batteryDamper = true;
  bool _benchRunning = false;
  bool _importRunning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.getTier(),
        _api.getBenchmarkHistory(),
        _api.listModels(),
      ]);
      if (!mounted) return;
      setState(() {
        _tier = results[0] as TierInfo;
        _benchmarks = results[1] as List<BenchmarkResult>;
        _models = results[2] as List<ModelEntry>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _tierLabel(TierLevel t) {
    switch (t) {
      case TierLevel.t0: return 'T0 · Nano';
      case TierLevel.t1: return 'T1 · Small';
      case TierLevel.t2: return 'T2 · Medium';
      case TierLevel.t3: return 'T3 · Large';
      case TierLevel.t4: return 'T4 · Heavy';
    }
  }

  Future<void> _handleAllowT4(bool value) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable T4 (Heavy) models?'),
          content: const Text(
            'T4 models require 16 GB+ RAM and will fully occupy your GPU. Battery drain will be significant.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable T4')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _api.setAllowT4(allow: value);
      setState(() => _allowT4 = value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _runBenchmark() async {
    setState(() => _benchRunning = true);
    try {
      await _api.runBenchmark();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _benchRunning = false);
    }
  }

  Future<void> _importGGUF() async {
    setState(() => _importRunning = true);
    try {
      await _api.importCustomGguf();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _importRunning = false);
    }
  }

  Future<void> _deleteModel(String modelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text('Remove "$modelId" from disk? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteModel(modelId);
      setState(() => _models.removeWhere((m) => m.modelId == modelId));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local AI')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Loading state
    if (_loading) return _buildSkeleton();

    // Error state
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final tier = _tier!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header badge
        _TierBadgeWidget(level: tier.active, isOverride: tier.override != TierOverride.auto),
        const SizedBox(height: 20),

        // Tier override
        _Section(
          title: 'Tier override',
          child: DropdownButtonFormField<TierOverride>(
            value: tier.override,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: TierOverride.values.map((v) {
              final labels = {
                TierOverride.auto: 'Auto (recommended)',
                TierOverride.t0: 'T0 — Nano (<1 GB)',
                TierOverride.t1: 'T1 — Small (1–4 GB)',
                TierOverride.t2: 'T2 — Medium (4–8 GB)',
                TierOverride.t3: 'T3 — Large (8–16 GB)',
                TierOverride.t4: 'T4 — Heavy (16 GB+)',
              };
              return DropdownMenuItem(value: v, child: Text(labels[v]!));
            }).toList(),
            onChanged: (v) async {
              if (v == null) return;
              try {
                await _api.setTierOverride(v == TierOverride.auto ? null : v);
                await _load();
              } catch (e) {
                if (!mounted) return;
                setState(() => _error = e.toString());
              }
            },
          ),
        ),

        // Toggles
        _Section(
          title: 'Options',
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Allow T4 (heavy models)'),
                subtitle: const Text('Requires 16 GB+ RAM'),
                value: _allowT4,
                onChanged: _handleAllowT4,
              ),
              SwitchListTile(
                title: const Text('Re-benchmark monthly'),
                subtitle: const Text('Auto re-run hardware benchmark every 30 days'),
                value: _reBenchMonthly,
                onChanged: (v) async {
                  await _api.setReBenchMonthly(enabled: v);
                  setState(() => _reBenchMonthly = v);
                },
              ),
              SwitchListTile(
                title: const Text('Battery damper'),
                subtitle: const Text('Limit inference to 80% GPU on battery'),
                value: _batteryDamper,
                onChanged: (v) => setState(() => _batteryDamper = v),
              ),
            ],
          ),
        ),

        // Benchmark history
        _Section(
          title: 'Benchmark history',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_benchmarks.isEmpty)
                const Text('No benchmarks yet.')
              else
                _SparklineWidget(values: _benchmarks.map((b) => b.toksPerSec).toList()),
              if (_benchmarks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Last: ${_benchmarks.first.toksPerSec} tok/s · ${_benchmarks.first.date}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _benchRunning ? null : _runBenchmark,
                child: Text(_benchRunning ? 'Running...' : 'Run benchmark again'),
              ),
            ],
          ),
        ),

        // Installed models
        _Section(
          title: 'Installed models',
          child: _models.isEmpty
              ? const Text('No models installed. Add a custom GGUF below.')
              : Column(
                  children: _models.map((m) => _ModelTile(
                    model: m,
                    onSetChatRole: () async {
                      await _api.setModelRole(m.modelId, 'chat');
                      await _load();
                    },
                    onDelete: () => _deleteModel(m.modelId),
                  )).toList(),
                ),
        ),

        // Add custom GGUF
        _Section(
          title: 'Add custom GGUF',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Import a .gguf file from device storage.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _importRunning ? null : _importGGUF,
                icon: const Icon(Icons.file_open),
                label: Text(_importRunning ? 'Importing...' : 'Choose file...'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(4, (_) => Container(
        height: 80,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
      )),
    );
  }
}

// --- Sub-widgets ---

class _TierBadgeWidget extends StatelessWidget {
  final TierLevel level;
  final bool isOverride;
  const _TierBadgeWidget({required this.level, required this.isOverride});

  @override
  Widget build(BuildContext context) {
    final labels = {
      TierLevel.t0: 'T0 · Nano',
      TierLevel.t1: 'T1 · Small',
      TierLevel.t2: 'T2 · Medium',
      TierLevel.t3: 'T3 · Large',
      TierLevel.t4: 'T4 · Heavy',
    };
    return Chip(
      label: Text('${labels[level]!} · ${isOverride ? "Override" : "Auto"}'),
      backgroundColor: const Color(0xFF0ea5e9).withOpacity(0.15),
      labelStyle: const TextStyle(color: Color(0xFF38bdf8), fontSize: 12),
      side: const BorderSide(color: Color(0xFF0ea5e9), width: 0.5),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white54,
                  letterSpacing: 1.2,
                )),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: child)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SparklineWidget extends StatelessWidget {
  final List<double> values;
  const _SparklineWidget({required this.values});

  @override
  Widget build(BuildContext context) {
    final max = values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 40,
      child: CustomPaint(painter: _SparklinePainter(values: values, max: max)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final double max;
  const _SparklinePainter({required this.values, required this.max});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0ea5e9).withOpacity(0.7)
      ..style = PaintingStyle.fill;
    final bw = (size.width / values.length) - 2;
    for (var i = 0; i < values.length; i++) {
      final bh = (values[i] / max) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (bw + 2), size.height - bh, bw, bh),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.values != values;
}

class _ModelTile extends StatelessWidget {
  final ModelEntry model;
  final VoidCallback onSetChatRole;
  final VoidCallback onDelete;
  const _ModelTile({required this.model, required this.onSetChatRole, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final sizGb = (model.sizeMb / 1024).toStringAsFixed(1);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(model.modelId, style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$sizGb GB${model.lastUsedAt != null ? " · last used ${model.lastUsedAt}" : ""}',
              style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: model.roles.map((r) => Chip(
              label: Text(r, style: const TextStyle(fontSize: 10)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: const Color(0xFF0ea5e9).withOpacity(0.12),
              labelStyle: const TextStyle(color: Color(0xFF38bdf8)),
              padding: EdgeInsets.zero,
            )).toList(),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'chat') onSetChatRole();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'chat', child: Text('Set as chat role')),
          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}
