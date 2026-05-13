import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'connection_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A single chunk from the nSelf knowledge base.
class KnowledgeChunk {
  final String id;
  final String category;
  final String title;
  final String content;
  final List<String> keywords;
  final List<String> commands;
  final List<String> tags;
  final List<String> suggestedActions;
  final List<String> userNotes;

  const KnowledgeChunk({
    required this.id,
    required this.category,
    required this.title,
    required this.content,
    this.keywords = const [],
    this.commands = const [],
    this.tags = const [],
    this.suggestedActions = const [],
    this.userNotes = const [],
  });

  factory KnowledgeChunk.fromJson(Map<String, dynamic> json) => KnowledgeChunk(
        id: json['id'] as String? ?? '',
        category: json['category'] as String? ?? '',
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        keywords: _toStringList(json['keywords']),
        commands: _toStringList(json['commands']),
        tags: _toStringList(json['tags']),
        suggestedActions: _toStringList(json['suggested_actions']),
        userNotes: _toStringList(json['user_notes']),
      );

  static List<String> _toStringList(dynamic val) {
    if (val is List) return val.map((e) => e.toString()).toList();
    return const [];
  }
}

/// A user annotation attached to a knowledge chunk.
class KnowledgeNote {
  final String id;
  final String chunkId;
  final String note;
  final String? userId;
  final DateTime createdAt;

  const KnowledgeNote({
    required this.id,
    required this.chunkId,
    required this.note,
    this.userId,
    required this.createdAt,
  });

  factory KnowledgeNote.fromJson(Map<String, dynamic> json) => KnowledgeNote(
        id: json['id'] as String,
        chunkId: json['chunk_id'] as String,
        note: json['note'] as String,
        userId: json['user_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Knowledge base version/meta info.
class KnowledgeVersion {
  final String version;
  final int schemaVersion;
  final String description;
  final List<String> categories;
  final int totalChunks;

  const KnowledgeVersion({
    required this.version,
    required this.schemaVersion,
    required this.description,
    required this.categories,
    required this.totalChunks,
  });

  factory KnowledgeVersion.fromJson(Map<String, dynamic> json) =>
      KnowledgeVersion(
        version: json['version'] as String? ?? '',
        schemaVersion: json['schema_version'] as int? ?? 1,
        description: json['description'] as String? ?? '',
        categories: KnowledgeChunk._toStringList(json['categories']),
        totalChunks: json['total_chunks'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class KnowledgeState {
  final bool isLoading;
  final List<KnowledgeChunk> results;
  final String? query;
  final String? selectedCategory;
  final KnowledgeVersion? versionInfo;
  final String? error;

  const KnowledgeState({
    this.isLoading = false,
    this.results = const [],
    this.query,
    this.selectedCategory,
    this.versionInfo,
    this.error,
  });

  KnowledgeState copyWith({
    bool? isLoading,
    List<KnowledgeChunk>? results,
    String? query,
    String? selectedCategory,
    KnowledgeVersion? versionInfo,
    String? error,
    bool clearError = false,
  }) =>
      KnowledgeState(
        isLoading: isLoading ?? this.isLoading,
        results: results ?? this.results,
        query: query ?? this.query,
        selectedCategory: selectedCategory ?? this.selectedCategory,
        versionInfo: versionInfo ?? this.versionInfo,
        error: clearError ? null : (error ?? this.error),
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class KnowledgeNotifier extends StateNotifier<KnowledgeState> {
  KnowledgeNotifier(this._ref) : super(const KnowledgeState());

  final Ref _ref;

  String get _serverUrl {
    try {
      return _ref.read(connectionProvider).activeServer?.url ?? '';
    } catch (_) {
      return '';
    }
  }

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  Future<void> search(String query, {String? category, int top = 5}) async {
    final base = _serverUrl;
    if (base.isEmpty) {
      state = state.copyWith(
          error: 'No server connected', isLoading: false);
      return;
    }

    state = state.copyWith(
        isLoading: true, query: query, clearError: true);

    try {
      final params = <String, String>{
        'q': query,
        'top': '$top',
        if (category case final String c) 'category': c,
      };
      final uri = Uri.parse('$base/claw/knowledge/search')
          .replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final chunks = (json['chunks'] as List? ?? [])
            .map((e) => KnowledgeChunk.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(
          isLoading: false,
          results: chunks,
          selectedCategory: category,
        );
      } else {
        state = state.copyWith(
            isLoading: false, error: 'Search failed (${resp.statusCode})');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearResults() {
    state = const KnowledgeState();
  }

  // -------------------------------------------------------------------------
  // Version info
  // -------------------------------------------------------------------------

  Future<KnowledgeVersion?> getVersionInfo() async {
    final base = _serverUrl;
    if (base.isEmpty) return null;
    try {
      final resp = await http
          .get(Uri.parse('$base/claw/knowledge/version'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final v = KnowledgeVersion.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
      state = state.copyWith(versionInfo: v);
      return v;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------------------

  Future<List<String>> getCategories() async {
    final base = _serverUrl;
    if (base.isEmpty) return const [];
    try {
      final resp = await http
          .get(Uri.parse('$base/claw/knowledge/categories'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return const [];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final cats = json['categories'] as List? ?? [];
      return cats
          .map((e) => (e as Map<String, dynamic>)['category'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // Notes
  // -------------------------------------------------------------------------

  Future<bool> addNote(String chunkId, String note) async {
    final base = _serverUrl;
    if (base.isEmpty) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$base/claw/knowledge/notes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'chunk_id': chunkId, 'note': note}),
          )
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteNote(String noteId) async {
    final base = _serverUrl;
    if (base.isEmpty) return false;
    try {
      final resp = await http
          .delete(Uri.parse('$base/claw/knowledge/notes/$noteId'))
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<KnowledgeNote>> getNotes({String? chunkId}) async {
    final base = _serverUrl;
    if (base.isEmpty) return const [];
    try {
      final params = <String, String>{
        if (chunkId case final String id) 'chunk_id': id,
      };
      final uri = Uri.parse('$base/claw/knowledge/notes')
          .replace(queryParameters: params.isEmpty ? null : params);
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return const [];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return (json['notes'] as List? ?? [])
          .map((e) => KnowledgeNote.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final knowledgeProvider =
    StateNotifierProvider<KnowledgeNotifier, KnowledgeState>(
  (ref) => KnowledgeNotifier(ref),
);
