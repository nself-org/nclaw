import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'connection_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A single chat message (user or assistant).
class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final String? tierSource;
  final String? modelUsed;
  final int? latencyMs;
  final int? inputTokens;
  final int? outputTokens;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.tierSource,
    this.modelUsed,
    this.latencyMs,
    this.inputTokens,
    this.outputTokens,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: json['role'] as String,
        content: json['content'] as String,
        tierSource: json['tier_source'] as String?,
        modelUsed: json['model_used'] as String?,
        latencyMs: json['latency_ms'] as int?,
        inputTokens: json['input_tokens'] as int?,
        outputTokens: json['output_tokens'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// A project grouping chat sessions.
class ChatProject {
  final String id;
  final String name;
  final String? color;
  final String? emoji;
  final String? systemPrompt;
  final DateTime createdAt;

  const ChatProject({
    required this.id,
    required this.name,
    this.color,
    this.emoji,
    this.systemPrompt,
    required this.createdAt,
  });

  factory ChatProject.fromJson(Map<String, dynamic> json) => ChatProject(
        id: json['id'] as String,
        name: json['name'] as String,
        color: json['color'] as String?,
        emoji: json['emoji'] as String?,
        systemPrompt: json['system_prompt'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  ChatProject copyWith({
    String? id,
    String? name,
    String? color,
    String? emoji,
    String? systemPrompt,
    DateTime? createdAt,
  }) {
    return ChatProject(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      emoji: emoji ?? this.emoji,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// A chat session.
///
/// Sessions whose [id] starts with `_local_` are pending — they exist only in
/// memory and will be created server-side on the first [sendMessage] call.
class ChatSession {
  final String id;
  final String? title;
  final String? autoTitle;
  final List<String> tags;
  final bool isAdminMode;
  final String? projectId;
  final String? parentSessionId;
  final DateTime createdAt;
  final List<ChatMessage> messages;

  /// Whether the server has more (older) messages to load.
  final bool hasMore;

  /// UUID of the oldest loaded message — used as cursor for loadMoreMessages.
  final String? oldestMessageId;

  /// Project to assign when this pending session is first committed to the
  /// server.
  final String? pendingProjectId;

  const ChatSession({
    required this.id,
    this.title,
    this.autoTitle,
    this.tags = const [],
    this.isAdminMode = false,
    this.projectId,
    this.parentSessionId,
    required this.createdAt,
    this.messages = const [],
    this.hasMore = true,
    this.oldestMessageId,
    this.pendingProjectId,
  });

  /// Display title: prefer user-set title, then auto-title, then placeholder.
  String get displayTitle => title ?? autoTitle ?? '\u014BClaw';

  /// True if this session has not yet been persisted to the server.
  bool get isPending => id.startsWith('_local_');

  ChatSession copyWith({
    String? id,
    String? title,
    String? autoTitle,
    List<String>? tags,
    bool? isAdminMode,
    String? projectId,
    String? parentSessionId,
    DateTime? createdAt,
    List<ChatMessage>? messages,
    bool? hasMore,
    String? oldestMessageId,
    String? pendingProjectId,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      autoTitle: autoTitle ?? this.autoTitle,
      tags: tags ?? this.tags,
      isAdminMode: isAdminMode ?? this.isAdminMode,
      projectId: projectId ?? this.projectId,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      createdAt: createdAt ?? this.createdAt,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      oldestMessageId: oldestMessageId ?? this.oldestMessageId,
      pendingProjectId: pendingProjectId ?? this.pendingProjectId,
    );
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags =
        rawTags is List ? rawTags.whereType<String>().toList() : <String>[];
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String?,
      autoTitle: json['auto_title'] as String?,
      tags: tags,
      isAdminMode: json['is_admin_mode'] as bool? ?? false,
      projectId: json['project_id'] as String?,
      parentSessionId: json['parent_session_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Drift suggestion returned by the backend when topic drift is detected
/// (T-1103).
class BreakoutSuggestion {
  final String newTopic;
  final String currentTopic;

  const BreakoutSuggestion({
    required this.newTopic,
    required this.currentTopic,
  });

  factory BreakoutSuggestion.fromJson(Map<String, dynamic> json) =>
      BreakoutSuggestion(
        newTopic: json['new_topic'] as String? ?? '',
        currentTopic: json['current_topic'] as String? ?? '',
      );
}

/// Combined state for the chat provider.
class ChatState {
  final List<ChatSession> sessions;
  final String? activeSessionId;
  final bool isStreaming;
  final String streamingContent;
  final List<ChatProject> projects;
  final String? currentProjectId;
  final bool isLoading;

  /// Most recent drift suggestion from the backend. Cleared when dismissed or
  /// when the active session changes.
  final BreakoutSuggestion? breakoutSuggestion;

  /// Non-null when a search is active — contains results from the backend.
  final List<ChatSession>? searchResults;

  /// The current search query string (empty = no search).
  final String searchQuery;

  const ChatState({
    this.sessions = const [],
    this.activeSessionId,
    this.isStreaming = false,
    this.streamingContent = '',
    this.projects = const [],
    this.currentProjectId,
    this.isLoading = false,
    this.breakoutSuggestion,
    this.searchResults,
    this.searchQuery = '',
  });

  /// The currently active session, if any.
  ChatSession? get activeSession {
    if (activeSessionId == null) return null;
    try {
      return sessions.firstWhere((s) => s.id == activeSessionId);
    } catch (_) {
      return null;
    }
  }

  /// Messages from the active session.
  List<ChatMessage> get messages => activeSession?.messages ?? const [];

  ChatState copyWith({
    List<ChatSession>? sessions,
    String? activeSessionId,
    bool? isStreaming,
    String? streamingContent,
    List<ChatProject>? projects,
    String? currentProjectId,
    bool? isLoading,
    BreakoutSuggestion? breakoutSuggestion,
    bool clearBreakout = false,
    List<ChatSession>? searchResults,
    bool clearSearch = false,
    String? searchQuery,
  }) {
    return ChatState(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingContent: streamingContent ?? this.streamingContent,
      projects: projects ?? this.projects,
      currentProjectId: currentProjectId ?? this.currentProjectId,
      isLoading: isLoading ?? this.isLoading,
      breakoutSuggestion:
          clearBreakout ? null : (breakoutSuggestion ?? this.breakoutSuggestion),
      searchResults: clearSearch ? null : (searchResults ?? this.searchResults),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

// ---------------------------------------------------------------------------
// ID generation
// ---------------------------------------------------------------------------

String _generateId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rand = (now % 999983).toString().padLeft(6, '0');
  return '${now}_$rand';
}

String _localId() => '_local_${_generateId()}';

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages chat sessions, projects, and message exchange with the nself-claw
/// backend.
///
/// When [_ref] is non-null (production), the notifier calls [_init] on
/// construction to load sessions and projects from the server. In tests, pass
/// no argument so [_init] is skipped and state can be set directly.
class ChatNotifier extends StateNotifier<ChatState> {
  final Ref? _ref;

  ChatNotifier([this._ref]) : super(const ChatState()) {
    if (_ref != null) _init();
  }

  // -------------------------------------------------------------------------
  // Internal HTTP helpers
  // -------------------------------------------------------------------------

  String get _serverUrl {
    try {
      return _ref?.read(connectionProvider).activeServer?.url ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>?> _get(String url) async {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> _getList(String url) async {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is List) return body;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(
    String url, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200 && resp.statusCode != 201) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _patch(String url, Map<String, dynamic> body) async {
    try {
      await http
          .patch(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort PATCH; failures are silently ignored.
    }
  }

  // -------------------------------------------------------------------------
  // Init
  // -------------------------------------------------------------------------

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    await Future.wait([loadProjects(), loadSessions()]);
    state = state.copyWith(isLoading: false);

    // Load messages for the first session (if not pending).
    final firstId = state.activeSessionId;
    if (firstId != null && !firstId.startsWith('_local_')) {
      await loadMessages(firstId);
    }
  }

  // -------------------------------------------------------------------------
  // Projects
  // -------------------------------------------------------------------------

  Future<void> loadProjects() async {
    final base = _serverUrl;
    if (base.isEmpty) return;

    // GET /claw/projects returns a plain JSON array.
    final raw = await _getList('$base/claw/projects');
    if (raw == null) return;
    final projects = raw
        .whereType<Map<String, dynamic>>()
        .map(ChatProject.fromJson)
        .toList();
    state = state.copyWith(projects: projects);
  }

  /// Create a new project on the server and add it to local state.
  Future<void> createProject(
    String name, {
    String? color,
    String? emoji,
    String? systemPrompt,
  }) async {
    final base = _serverUrl;
    if (base.isEmpty) return;

    final data = await _post('$base/claw/projects', body: {
      'name': name,
      'color': ?color,
      'emoji': ?emoji,
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'system_prompt': systemPrompt,
    });
    if (data == null) return;

    final project = ChatProject.fromJson(data);
    state = state.copyWith(projects: [project, ...state.projects]);
  }

  /// Rename a project on the server and in local state.
  Future<void> renameProject(String id, String name) async {
    await _patchProject(id, {'name': name});
    _updateProject(id, (p) => p.copyWith(name: name));
  }

  /// Change a project's colour on the server and in local state.
  Future<void> changeProjectColor(String id, String color) async {
    await _patchProject(id, {'color': color});
    _updateProject(id, (p) => p.copyWith(color: color));
  }

  /// Change a project's emoji icon on the server and in local state.
  Future<void> changeProjectEmoji(String id, String emoji) async {
    await _patchProject(id, {'emoji': emoji});
    _updateProject(id, (p) => p.copyWith(emoji: emoji));
  }

  /// Update a project's system prompt on the server and in local state.
  Future<void> updateProjectSystemPrompt(String id, String prompt) async {
    await _patchProject(id, {'system_prompt': prompt});
    _updateProject(id, (p) => p.copyWith(systemPrompt: prompt));
  }

  /// Archive a project and remove it from local state.
  Future<void> archiveProject(String id) async {
    await _patchProject(id, {'archived': true});
    final updated = state.projects.where((p) => p.id != id).toList();
    state = state.copyWith(projects: updated);
  }

  // -------------------------------------------------------------------------
  // Sessions
  // -------------------------------------------------------------------------

  /// Load sessions from the server and replace the local list.
  Future<void> loadSessions() async {
    final base = _serverUrl;
    if (base.isEmpty) {
      _ensureLocalSession();
      return;
    }
    final data = await _get('$base/claw/sessions?page_size=50');
    if (data == null) {
      _ensureLocalSession();
      return;
    }
    final raw = (data['sessions'] as List<dynamic>?) ?? [];
    final sessions = raw
        .whereType<Map<String, dynamic>>()
        .map(ChatSession.fromJson)
        .toList();

    if (sessions.isEmpty) {
      _ensureLocalSession();
    } else {
      state = state.copyWith(
        sessions: sessions,
        activeSessionId: sessions.first.id,
      );
    }
  }

  /// Load the newest 20 messages for [sessionId].
  Future<void> loadMessages(String sessionId) async {
    if (sessionId.startsWith('_local_')) return;
    final base = _serverUrl;
    if (base.isEmpty) return;

    final data =
        await _get('$base/claw/sessions/$sessionId/messages?limit=20');
    if (data == null) return;

    final raw = (data['messages'] as List<dynamic>?) ?? [];
    final msgs = raw
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
    final hasMore = data['has_more'] as bool? ?? false;
    final oldest = msgs.isNotEmpty ? msgs.last.id : null;

    _updateSession(sessionId, (s) => s.copyWith(
          messages: msgs,
          hasMore: hasMore,
          oldestMessageId: oldest,
        ));
  }

  /// Load older messages (cursor pagination) for [sessionId].
  Future<void> loadMoreMessages(String sessionId) async {
    if (sessionId.startsWith('_local_')) return;
    final session = state.sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null || !session.hasMore) return;

    final base = _serverUrl;
    if (base.isEmpty) return;

    final before = session.oldestMessageId;
    final url = before != null
        ? '$base/claw/sessions/$sessionId/messages?limit=20&before=$before'
        : '$base/claw/sessions/$sessionId/messages?limit=20';

    final data = await _get(url);
    if (data == null) return;

    final raw = (data['messages'] as List<dynamic>?) ?? [];
    final older = raw
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
    final hasMore = data['has_more'] as bool? ?? false;
    final oldest =
        older.isNotEmpty ? older.last.id : session.oldestMessageId;

    _updateSession(sessionId, (s) => s.copyWith(
          messages: [...s.messages, ...older],
          hasMore: hasMore,
          oldestMessageId: oldest,
        ));
  }

  // -------------------------------------------------------------------------
  // Session lifecycle
  // -------------------------------------------------------------------------

  /// Create a new local (pending) session, optionally scoped to [projectId].
  ///
  /// The session is committed to the server on the first [sendMessage] call.
  void createSession({String? projectId}) {
    final session = ChatSession(
      id: _localId(),
      createdAt: DateTime.now(),
      pendingProjectId: projectId,
    );
    state = state.copyWith(
      sessions: [session, ...state.sessions],
      activeSessionId: session.id,
      clearBreakout: true,
    );
  }

  /// Switch to an existing session by id, loading messages if not yet loaded.
  Future<void> switchSession(String id) async {
    state = state.copyWith(activeSessionId: id, clearBreakout: true);
    final session = state.sessions.where((s) => s.id == id).firstOrNull;
    if (session != null && session.messages.isEmpty && !session.isPending) {
      await loadMessages(id);
    }
  }

  /// Alias for [createSession] — used by the FAB and session-list "New" button.
  void newSession() => createSession();

  /// Branch the given session into a sub-session.
  ///
  /// Calls `POST /claw/sessions/{id}/branch` and opens the returned session.
  Future<void> branchSession(String sessionId) async {
    final base = _serverUrl;
    if (base.isEmpty) return;

    final data = await _post('$base/claw/sessions/$sessionId/branch');
    if (data == null) return;

    final newSession = ChatSession.fromJson(data);
    state = state.copyWith(
      sessions: [newSession, ...state.sessions],
      activeSessionId: newSession.id,
      clearBreakout: true,
    );
  }

  /// Dismiss the current breakout suggestion banner.
  void dismissBreakout() => state = state.copyWith(clearBreakout: true);

  // -------------------------------------------------------------------------
  // Session mutations (archive, rename, move)
  // -------------------------------------------------------------------------

  /// Archive [sessionId] on the server and remove it from the local list.
  Future<void> archiveSession(String sessionId) async {
    final base = _serverUrl;
    if (base.isNotEmpty) {
      await _patch('$base/claw/sessions/$sessionId', {'archived': true});
    }
    final updated = state.sessions.where((s) => s.id != sessionId).toList();
    final newActive = state.activeSessionId == sessionId
        ? (updated.isNotEmpty ? updated.first.id : null)
        : state.activeSessionId;
    state = state.copyWith(sessions: updated, activeSessionId: newActive);
  }

  /// Rename [sessionId] to [title] on the server and update local state.
  Future<void> renameSession(String sessionId, String title) async {
    final base = _serverUrl;
    if (base.isNotEmpty) {
      await _patch('$base/claw/sessions/$sessionId', {'title': title});
    }
    _updateSession(sessionId, (s) => s.copyWith(title: title));
  }

  /// Move [sessionId] to [projectId] (null to remove from project).
  Future<void> moveSessionToProject(
      String sessionId, String? projectId) async {
    final base = _serverUrl;
    if (base.isNotEmpty) {
      await _patch('$base/claw/sessions/$sessionId',
          {'project_id': projectId});
    }
    _updateSession(
        sessionId, (s) => s.copyWith(projectId: projectId ?? s.projectId));
  }

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  /// Search sessions via GET /claw/sessions/search?q=.
  Future<void> searchSessions(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      state = state.copyWith(clearSearch: true, searchQuery: '');
      return;
    }
    state = state.copyWith(searchQuery: q);
    final base = _serverUrl;
    if (base.isEmpty) return;
    final data = await _get('$base/claw/sessions/search?q=${Uri.encodeQueryComponent(q)}');
    if (data == null) return;
    // Response is either {"sessions": [...]} or a plain array.
    final raw = data['sessions'] as List<dynamic>? ??
        (data.values.firstOrNull is List
            ? data.values.firstOrNull as List<dynamic>
            : []);
    final results = raw
        .whereType<Map<String, dynamic>>()
        .map(ChatSession.fromJson)
        .toList();
    // Only apply if query is still the same (debounce guard).
    if (state.searchQuery == q) {
      state = state.copyWith(searchResults: results);
    }
  }

  /// Clear the current search and return to the full session list.
  void clearSearch() =>
      state = state.copyWith(clearSearch: true, searchQuery: '');

  // -------------------------------------------------------------------------
  // Messaging
  // -------------------------------------------------------------------------

  /// Send a user message and fetch the assistant response.
  ///
  /// If the active session is pending (local-only), [session_id] is omitted
  /// so the server creates a new session, which is then promoted locally.
  Future<void> sendMessage(String text, String serverUrl) async {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return;
    if (serverUrl.isEmpty) {
      _appendError(sessionId, 'No server connected');
      return;
    }

    // Optimistically add user message.
    _appendMessage(
      sessionId,
      ChatMessage(
        id: _localId(),
        role: 'user',
        content: text,
        createdAt: DateTime.now(),
      ),
    );
    state = state.copyWith(isStreaming: true, streamingContent: '');

    try {
      final isPending = sessionId.startsWith('_local_');
      final session =
          state.sessions.where((s) => s.id == sessionId).firstOrNull;

      final body = <String, dynamic>{
        'message': text,
        'stream': false,
        if (!isPending) 'session_id': sessionId,
      };

      final resp = await http
          .post(
            Uri.parse('$serverUrl/claw/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final responseText = data['response'] as String? ?? '';
      final serverSessionId = data['session_id'] as String?;
      final tierSource = data['tier_source'] as String?;
      final latencyMs = data['latency_ms'] as int?;
      final tokens = data['tokens'] as int?;

      // Promote pending session to server-assigned id.
      String activeId = sessionId;
      if (isPending && serverSessionId != null) {
        activeId = serverSessionId;
        _promotePendingSession(
          pendingId: sessionId,
          serverId: serverSessionId,
          serverUrl: serverUrl,
          pendingProjectId: session?.pendingProjectId,
        );
      }

      // Add the assistant reply.
      _appendMessage(
        activeId,
        ChatMessage(
          id: _localId(),
          role: 'assistant',
          content: responseText,
          tierSource: tierSource,
          latencyMs: latencyMs,
          outputTokens: tokens,
          createdAt: DateTime.now(),
        ),
      );

      // Propagate drift suggestion if present.
      final rawBreakout = data['breakout_suggestion'];
      if (rawBreakout is Map<String, dynamic>) {
        state = state.copyWith(
          breakoutSuggestion: BreakoutSuggestion.fromJson(rawBreakout),
        );
      }
    } catch (e) {
      _appendError(sessionId, 'Error: $e');
    } finally {
      state = state.copyWith(isStreaming: false, streamingContent: '');
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  Future<void> _patchProject(String id, Map<String, dynamic> body) async {
    final base = _serverUrl;
    if (base.isNotEmpty) {
      await _patch('$base/claw/projects/$id', body);
    }
  }

  void _updateProject(String id, ChatProject Function(ChatProject) transform) {
    final updated =
        state.projects.map((p) => p.id == id ? transform(p) : p).toList();
    state = state.copyWith(projects: updated);
  }

  void _ensureLocalSession() {
    if (state.sessions.isNotEmpty) return;
    final session =
        ChatSession(id: _localId(), createdAt: DateTime.now());
    state = ChatState(
      sessions: [session],
      activeSessionId: session.id,
    );
  }

  /// Replace a pending session with the server-assigned id, preserving
  /// messages and other fields. PATCHes project_id if needed (fire-and-forget).
  void _promotePendingSession({
    required String pendingId,
    required String serverId,
    required String serverUrl,
    String? pendingProjectId,
  }) {
    final idx = state.sessions.indexWhere((s) => s.id == pendingId);
    if (idx < 0) return;
    final old = state.sessions[idx];
    final promoted = old.copyWith(
      id: serverId,
      projectId: pendingProjectId,
    );
    final updated = [...state.sessions];
    updated[idx] = promoted;
    state = state.copyWith(sessions: updated, activeSessionId: serverId);

    if (pendingProjectId != null && serverUrl.isNotEmpty) {
      _patch(
        '$serverUrl/claw/sessions/$serverId',
        {'project_id': pendingProjectId},
      );
    }
  }

  void _updateSession(
      String id, ChatSession Function(ChatSession) transform) {
    final updated =
        state.sessions.map((s) => s.id == id ? transform(s) : s).toList();
    state = state.copyWith(sessions: updated);
  }

  void _appendMessage(String sessionId, ChatMessage message) {
    _updateSession(
      sessionId,
      (s) => s.copyWith(messages: [...s.messages, message]),
    );
  }

  void _appendError(String sessionId, String text) {
    _appendMessage(
      sessionId,
      ChatMessage(
        id: _localId(),
        role: 'assistant',
        content: text,
        createdAt: DateTime.now(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// The primary chat provider.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>(
  (ref) => ChatNotifier(ref),
);

/// Convenience provider for the list of chat sessions.
final chatSessionsProvider = Provider<List<ChatSession>>(
  (ref) => ref.watch(chatProvider).sessions,
);

/// Convenience provider for the list of projects.
final chatProjectsProvider = Provider<List<ChatProject>>(
  (ref) => ref.watch(chatProvider).projects,
);
