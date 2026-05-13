// T-1200: DigestViewer — shows current proactive digest, pull-to-refresh,
// navigable from notification taps via named route '/digest'.

import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/connection_provider.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _DigestState {
  final bool loading;
  final String? text;
  final DateTime? generatedAt;
  final String? error;

  const _DigestState({
    this.loading = false,
    this.text,
    this.generatedAt,
    this.error,
  });

  _DigestState copyWith({
    bool? loading,
    String? text,
    DateTime? generatedAt,
    String? error,
  }) =>
      _DigestState(
        loading: loading ?? this.loading,
        text: text ?? this.text,
        generatedAt: generatedAt ?? this.generatedAt,
        error: error ?? this.error,
      );
}

class _DigestNotifier extends StateNotifier<_DigestState> {
  final String? serverUrl;

  _DigestNotifier(this.serverUrl) : super(const _DigestState(loading: true)) {
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
      final uri = Uri.parse('$url/claw/proactive/digest');
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawAt = json['generated_at'] as String?;
        state = state.copyWith(
          loading: false,
          text: json['text'] as String? ?? '',
          generatedAt: rawAt != null ? DateTime.tryParse(rawAt) : null,
        );
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
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DigestViewerScreen extends ConsumerStatefulWidget {
  const DigestViewerScreen({super.key});

  static const routeName = '/digest';

  @override
  ConsumerState<DigestViewerScreen> createState() => _DigestViewerScreenState();
}

class _DigestViewerScreenState extends ConsumerState<DigestViewerScreen> {
  late final StateNotifierProvider<_DigestNotifier, _DigestState> _provider;

  @override
  void initState() {
    super.initState();
    final server = ref.read(connectionProvider).activeServer;
    _provider = StateNotifierProvider<_DigestNotifier, _DigestState>(
      (ref) => _DigestNotifier(server?.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Digest'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(_provider.notifier).load(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(_provider.notifier).load(),
        child: _buildBody(state, theme),
      ),
    );
  }

  Widget _buildBody(_DigestState state, ThemeData theme) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 48),
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
        ],
      );
    }

    final text = state.text ?? '';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (state.generatedAt != null)
          _GeneratedAtBanner(generatedAt: state.generatedAt!),
        const SizedBox(height: 12),
        if (text.isEmpty)
          _EmptyDigest(theme: theme)
        else
          _DigestCard(text: text, theme: theme),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _GeneratedAtBanner extends StatelessWidget {
  const _GeneratedAtBanner({required this.generatedAt});

  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final local = generatedAt.toLocal();
    final label =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        const Icon(Icons.schedule, size: 14),
        const SizedBox(width: 6),
        Text(
          'Generated $label',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _EmptyDigest extends StatelessWidget {
  const _EmptyDigest({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48,
              color: theme.colorScheme.onSurface.withAlpha(80)),
          const SizedBox(height: 16),
          Text(
            'Nothing to digest yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(160)),
          ),
          const SizedBox(height: 6),
          Text(
            'Pull down to refresh.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(100)),
          ),
        ],
      ),
    );
  }
}

class _DigestCard extends StatelessWidget {
  const _DigestCard({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
      ),
    );
  }
}
