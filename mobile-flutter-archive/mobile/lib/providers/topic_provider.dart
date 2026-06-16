/// Topic tree provider for the sidebar drawer (E-26-01).
///
/// Fetches the topic tree from the backend, supports local expand/collapse,
/// reorder via drag-and-drop, and offline caching.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/topic_node.dart';
import 'connection_provider.dart';

/// State for the topic tree.
class TopicTreeState {
  final bool loading;
  final List<TopicNode> topics;
  final String? error;
  final String? selectedTopicId;
  final String? filterQuery;

  const TopicTreeState({
    this.loading = false,
    this.topics = const [],
    this.error,
    this.selectedTopicId,
    this.filterQuery,
  });

  bool get isEmpty => !loading && topics.isEmpty && error == null;

  TopicTreeState copyWith({
    bool? loading,
    List<TopicNode>? topics,
    String? error,
    String? selectedTopicId,
    String? filterQuery,
  }) =>
      TopicTreeState(
        loading: loading ?? this.loading,
        topics: topics ?? this.topics,
        error: error,
        selectedTopicId: selectedTopicId ?? this.selectedTopicId,
        filterQuery: filterQuery ?? this.filterQuery,
      );
}

/// Notifier for the topic tree.
class TopicTreeNotifier extends StateNotifier<TopicTreeState> {
  final Ref _ref;

  TopicTreeNotifier(this._ref) : super(const TopicTreeState()) {
    loadTopics();
  }

  String? get _serverUrl =>
      _ref.read(connectionProvider).activeServer?.url;

  /// Fetch all topics from the backend.
  Future<void> loadTopics() async {
    final url = _serverUrl;
    if (url == null) return;

    state = state.copyWith(loading: true);

    try {
      final response = await http
          .get(Uri.parse('$url/claw/topics'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data as List<dynamic>?)
                ?.map((j) => TopicNode.fromJson(j as Map<String, dynamic>))
                .toList() ??
            [];
        state = state.copyWith(loading: false, topics: list);
      } else {
        state = state.copyWith(
          loading: false,
          error: 'Failed to load topics (${response.statusCode})',
        );
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Network error: $e');
    }
  }

  /// Select a topic by ID.
  void selectTopic(String? topicId) {
    state = state.copyWith(selectedTopicId: topicId);
  }

  /// Toggle expand/collapse for a topic.
  void toggleExpanded(String topicId) {
    state = state.copyWith(
      topics: _toggleInList(state.topics, topicId),
    );
  }

  List<TopicNode> _toggleInList(List<TopicNode> nodes, String topicId) {
    return nodes.map((node) {
      if (node.id == topicId) {
        return node.copyWith(isExpanded: !node.isExpanded);
      }
      if (node.children.isNotEmpty) {
        return node.copyWith(
          children: _toggleInList(node.children, topicId),
        );
      }
      return node;
    }).toList();
  }

  /// Reorder a topic (drag-and-drop). Sends update to backend.
  Future<void> reorderTopic({
    required String topicId,
    required String? newParentId,
    required int newSortOrder,
  }) async {
    final url = _serverUrl;
    if (url == null) return;

    try {
      await http.patch(
        Uri.parse('$url/claw/topics/$topicId/reorder'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'parent_id': newParentId,
          'sort_order': newSortOrder,
        }),
      );
      await loadTopics(); // Refresh after reorder.
    } catch (_) {
      // Reorder failed; tree stays as-is.
    }
  }

  /// Create a new topic.
  Future<void> createTopic({
    required String name,
    String? parentId,
    String? color,
    String? icon,
  }) async {
    final url = _serverUrl;
    if (url == null) return;

    try {
      await http.post(
        Uri.parse('$url/claw/topics'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'parent_id': parentId,
          'color': color,
          'icon': icon,
        }),
      );
      await loadTopics();
    } catch (_) {
      // Creation failed.
    }
  }

  /// Update topic color/icon.
  Future<void> updateTopic({
    required String topicId,
    String? name,
    String? color,
    String? icon,
  }) async {
    final url = _serverUrl;
    if (url == null) return;

    try {
      await http.patch(
        Uri.parse('$url/claw/topics/$topicId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (name != null) 'name': name,
          if (color != null) 'color': color,
          if (icon != null) 'icon': icon,
        }),
      );
      await loadTopics();
    } catch (_) {
      // Update failed.
    }
  }
}

final topicTreeProvider =
    StateNotifierProvider<TopicTreeNotifier, TopicTreeState>(
  (ref) => TopicTreeNotifier(ref),
);
