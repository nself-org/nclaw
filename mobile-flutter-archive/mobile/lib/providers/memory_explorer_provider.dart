/// Memory explorer provider for the 4-tab memory screen (E-26-03).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/memory_record.dart';
import 'connection_provider.dart';

class MemoryExplorerState {
  final bool loading;
  final List<MemoryRecord> facts;
  final List<MemoryRecord> decisions;
  final List<MemoryRecord> entities;
  final List<MemoryRecord> timeline;
  final String? error;

  const MemoryExplorerState({
    this.loading = false,
    this.facts = const [],
    this.decisions = const [],
    this.entities = const [],
    this.timeline = const [],
    this.error,
  });

  MemoryExplorerState copyWith({
    bool? loading,
    List<MemoryRecord>? facts,
    List<MemoryRecord>? decisions,
    List<MemoryRecord>? entities,
    List<MemoryRecord>? timeline,
    String? error,
  }) =>
      MemoryExplorerState(
        loading: loading ?? this.loading,
        facts: facts ?? this.facts,
        decisions: decisions ?? this.decisions,
        entities: entities ?? this.entities,
        timeline: timeline ?? this.timeline,
        error: error,
      );
}

class MemoryExplorerNotifier extends StateNotifier<MemoryExplorerState> {
  final Ref _ref;

  MemoryExplorerNotifier(this._ref) : super(const MemoryExplorerState()) {
    loadAll();
  }

  String? get _serverUrl =>
      _ref.read(connectionProvider).activeServer?.url;

  Future<void> loadAll() async {
    final url = _serverUrl;
    if (url == null) return;

    state = state.copyWith(loading: true);

    try {
      final response = await http
          .get(Uri.parse('$url/claw/memory?include_all_types=true'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>? ?? [];
        final records = data
            .map((j) => MemoryRecord.fromJson(j as Map<String, dynamic>))
            .toList();

        state = state.copyWith(
          loading: false,
          facts: records.where((r) => r.entityType == 'fact').toList(),
          decisions: records.where((r) => r.entityType == 'decision').toList(),
          entities: records.where((r) => r.entityType == 'entity').toList(),
          timeline: records..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
      } else {
        state = state.copyWith(
          loading: false,
          error: 'Failed to load memories (${response.statusCode})',
        );
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Network error: $e');
    }
  }
}

final memoryExplorerProvider =
    StateNotifierProvider<MemoryExplorerNotifier, MemoryExplorerState>(
  (ref) => MemoryExplorerNotifier(ref),
);
