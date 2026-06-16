// Unit tests for chat_provider + knowledge_provider state classes.

import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/models/memory_record.dart';
import 'package:nself_claw/providers/chat_provider.dart';
import 'package:nself_claw/providers/knowledge_provider.dart';
import 'package:nself_claw/providers/memory_explorer_provider.dart';

void main() {
  final created = DateTime.utc(2026, 1, 1);

  // ---------------------------------------------------------------------------
  // ChatMessage
  // ---------------------------------------------------------------------------
  group('ChatMessage', () {
    test('constructor defaults knowledgeUsed=false and memoriesUsed=0', () {
      final m = ChatMessage(
        id: 'm1',
        role: 'user',
        content: 'hello',
        createdAt: created,
      );
      expect(m.knowledgeUsed, false);
      expect(m.memoriesUsed, 0);
      expect(m.tierSource, isNull);
      expect(m.modelUsed, isNull);
    });

    test('fromJson parses core fields', () {
      final m = ChatMessage.fromJson({
        'id': 'm1',
        'role': 'assistant',
        'content': 'hi',
        'tier_source': 'cache',
        'model_used': 'claude',
        'latency_ms': 120,
        'input_tokens': 10,
        'output_tokens': 20,
        'created_at': created.toIso8601String(),
      });
      expect(m.id, 'm1');
      expect(m.role, 'assistant');
      expect(m.content, 'hi');
      expect(m.tierSource, 'cache');
      expect(m.modelUsed, 'claude');
      expect(m.latencyMs, 120);
      expect(m.inputTokens, 10);
      expect(m.outputTokens, 20);
    });
  });

  // ---------------------------------------------------------------------------
  // ChatProject
  // ---------------------------------------------------------------------------
  group('ChatProject', () {
    test('fromJson parses core fields', () {
      final p = ChatProject.fromJson({
        'id': 'p1',
        'name': 'Work',
        'color': '#FF0000',
        'emoji': '💼',
        'system_prompt': 'Be concise.',
        'created_at': created.toIso8601String(),
      });
      expect(p.id, 'p1');
      expect(p.name, 'Work');
      expect(p.color, '#FF0000');
      expect(p.emoji, '💼');
      expect(p.systemPrompt, 'Be concise.');
    });

    test('copyWith replaces specified fields', () {
      final p = ChatProject(
        id: 'p1',
        name: 'Work',
        createdAt: created,
      );
      final p2 = p.copyWith(name: 'W2', emoji: 'X');
      expect(p2.id, 'p1');
      expect(p2.name, 'W2');
      expect(p2.emoji, 'X');
    });

    test('copyWith handles color and systemPrompt fields', () {
      final p = ChatProject(
        id: 'p1',
        name: 'Work',
        createdAt: created,
      );
      final p2 = p.copyWith(color: '#333', systemPrompt: 'Be terse.');
      expect(p2.color, '#333');
      expect(p2.systemPrompt, 'Be terse.');
      // Name and id preserved
      expect(p2.id, 'p1');
      expect(p2.name, 'Work');
    });

    test('copyWith with id override replaces the id', () {
      final p = ChatProject(
        id: 'old',
        name: 'n',
        createdAt: created,
      );
      final p2 = p.copyWith(id: 'new');
      expect(p2.id, 'new');
    });
  });

  // ---------------------------------------------------------------------------
  // ChatSession
  // ---------------------------------------------------------------------------
  group('ChatSession', () {
    test('isPending true when id starts with _local_', () {
      final s = ChatSession(
        id: '_local_abc',
        createdAt: created,
      );
      expect(s.isPending, true);
    });

    test('isPending false for persisted sessions', () {
      final s = ChatSession(
        id: 'real-id',
        createdAt: created,
      );
      expect(s.isPending, false);
    });

    test('fromJson parses tags as List<String>', () {
      final s = ChatSession.fromJson({
        'id': 's1',
        'title': 'T',
        'tags': ['a', 'b', 42, 'c'],
        'is_admin_mode': true,
        'project_id': 'p1',
        'parent_session_id': 'parent',
        'auto_title': 'AT',
        'created_at': created.toIso8601String(),
      });
      expect(s.id, 's1');
      expect(s.title, 'T');
      expect(s.tags, ['a', 'b', 'c']); // non-strings filtered
      expect(s.isAdminMode, true);
      expect(s.projectId, 'p1');
      expect(s.parentSessionId, 'parent');
      expect(s.autoTitle, 'AT');
    });

    test('fromJson handles missing tags gracefully', () {
      final s = ChatSession.fromJson({
        'id': 's1',
        'created_at': created.toIso8601String(),
      });
      expect(s.tags, isEmpty);
      expect(s.isAdminMode, false);
    });

    test('copyWith preserves unspecified fields', () {
      final s = ChatSession(
        id: 's1',
        title: 'T',
        tags: const ['a'],
        createdAt: created,
      );
      final s2 = s.copyWith(title: 'T2');
      expect(s2.id, 's1');
      expect(s2.title, 'T2');
      expect(s2.tags, ['a']);
    });
  });

  // ---------------------------------------------------------------------------
  // BreakoutSuggestion
  // ---------------------------------------------------------------------------
  group('BreakoutSuggestion', () {
    test('fromJson with both fields', () {
      final b = BreakoutSuggestion.fromJson({
        'new_topic': 'Nutrition',
        'current_topic': 'Work',
      });
      expect(b.newTopic, 'Nutrition');
      expect(b.currentTopic, 'Work');
    });

    test('fromJson with missing fields defaults to empty strings', () {
      final b = BreakoutSuggestion.fromJson({});
      expect(b.newTopic, '');
      expect(b.currentTopic, '');
    });
  });

  // ---------------------------------------------------------------------------
  // ChatState
  // ---------------------------------------------------------------------------
  group('ChatState', () {
    final s1 = ChatSession(
      id: 'a',
      title: 'A',
      createdAt: created,
      messages: [
        ChatMessage(id: 'm1', role: 'user', content: 'hi', createdAt: created),
      ],
    );
    final s2 = ChatSession(
      id: 'b',
      parentSessionId: 'a',
      createdAt: created,
    );

    test('defaults', () {
      const s = ChatState();
      expect(s.sessions, isEmpty);
      expect(s.activeSessionId, isNull);
      expect(s.isStreaming, false);
      expect(s.streamingContent, '');
      expect(s.projects, isEmpty);
      expect(s.isLoading, false);
      expect(s.breakoutSuggestion, isNull);
      expect(s.searchResults, isNull);
      expect(s.searchQuery, '');
      expect(s.activeSession, isNull);
      expect(s.messages, isEmpty);
      expect(s.parentSession, isNull);
    });

    test('activeSession finds by id', () {
      final state = ChatState(
        sessions: [s1, s2],
        activeSessionId: 'a',
      );
      expect(state.activeSession?.id, 'a');
      expect(state.messages, hasLength(1));
    });

    test('activeSession returns null when id not found', () {
      final state = ChatState(
        sessions: [s1],
        activeSessionId: 'ghost',
      );
      expect(state.activeSession, isNull);
      expect(state.messages, isEmpty);
    });

    test('parentSession resolves via parentSessionId', () {
      final state = ChatState(
        sessions: [s1, s2],
        activeSessionId: 'b',
      );
      expect(state.parentSession?.id, 'a');
    });

    test('parentSession null when active has no parent', () {
      final state = ChatState(
        sessions: [s1],
        activeSessionId: 'a',
      );
      expect(state.parentSession, isNull);
    });

    test('copyWith replaces specified and preserves rest', () {
      const base = ChatState(searchQuery: 'q', isLoading: true);
      final updated = base.copyWith(isStreaming: true, isLoading: false);
      expect(updated.isStreaming, true);
      expect(updated.isLoading, false);
      expect(updated.searchQuery, 'q');
    });

    test('copyWith clearBreakout drops breakout', () {
      const base = ChatState(
          breakoutSuggestion:
              BreakoutSuggestion(newTopic: 'n', currentTopic: 'c'));
      final updated = base.copyWith(clearBreakout: true);
      expect(updated.breakoutSuggestion, isNull);
    });

    test('copyWith clearSearch drops searchResults', () {
      final base = ChatState(searchResults: const []);
      final updated = base.copyWith(clearSearch: true);
      expect(updated.searchResults, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // KnowledgeChunk / Note / Version
  // ---------------------------------------------------------------------------
  group('KnowledgeChunk', () {
    test('fromJson with full payload', () {
      final c = KnowledgeChunk.fromJson({
        'id': 'c1',
        'category': 'cli',
        'title': 'init',
        'content': 'Creates a project',
        'keywords': ['start', 'new'],
        'commands': ['nself init'],
        'tags': ['beginner'],
        'suggested_actions': ['run'],
        'user_notes': ['worked for me'],
      });
      expect(c.id, 'c1');
      expect(c.category, 'cli');
      expect(c.title, 'init');
      expect(c.keywords, ['start', 'new']);
      expect(c.commands, ['nself init']);
      expect(c.tags, ['beginner']);
      expect(c.suggestedActions, ['run']);
      expect(c.userNotes, ['worked for me']);
    });

    test('fromJson with missing lists defaults to empty', () {
      final c = KnowledgeChunk.fromJson({'id': 'c'});
      expect(c.title, '');
      expect(c.content, '');
      expect(c.keywords, isEmpty);
      expect(c.commands, isEmpty);
      expect(c.tags, isEmpty);
    });

    test('fromJson coerces mixed-type list items to string', () {
      final c = KnowledgeChunk.fromJson({
        'id': 'c',
        'keywords': ['x', 42, 3.14, true],
      });
      expect(c.keywords, ['x', '42', '3.14', 'true']);
    });
  });

  group('KnowledgeNote', () {
    test('fromJson parses all fields', () {
      final n = KnowledgeNote.fromJson({
        'id': 'n1',
        'chunk_id': 'c1',
        'note': 'Hello',
        'user_id': 'u1',
        'created_at': created.toIso8601String(),
      });
      expect(n.id, 'n1');
      expect(n.chunkId, 'c1');
      expect(n.note, 'Hello');
      expect(n.userId, 'u1');
      expect(n.createdAt, created);
    });
  });

  group('KnowledgeVersion', () {
    test('fromJson parses all fields', () {
      final v = KnowledgeVersion.fromJson({
        'version': '1.0.0',
        'schema_version': 2,
        'description': 'CLI docs',
        'categories': ['cli', 'env'],
        'total_chunks': 120,
      });
      expect(v.version, '1.0.0');
      expect(v.schemaVersion, 2);
      expect(v.description, 'CLI docs');
      expect(v.categories, ['cli', 'env']);
      expect(v.totalChunks, 120);
    });

    test('fromJson applies defaults for missing fields', () {
      final v = KnowledgeVersion.fromJson({});
      expect(v.version, '');
      expect(v.schemaVersion, 1);
      expect(v.description, '');
      expect(v.categories, isEmpty);
      expect(v.totalChunks, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // KnowledgeState
  // ---------------------------------------------------------------------------
  group('KnowledgeState', () {
    test('defaults', () {
      const s = KnowledgeState();
      expect(s.isLoading, false);
      expect(s.results, isEmpty);
      expect(s.query, isNull);
      expect(s.selectedCategory, isNull);
      expect(s.versionInfo, isNull);
      expect(s.error, isNull);
    });

    test('copyWith replaces specified fields', () {
      const base = KnowledgeState();
      final updated = base.copyWith(
        isLoading: true,
        query: 'init',
        selectedCategory: 'cli',
      );
      expect(updated.isLoading, true);
      expect(updated.query, 'init');
      expect(updated.selectedCategory, 'cli');
    });

    test('copyWith clearError drops error', () {
      const base = KnowledgeState(error: 'bad');
      final updated = base.copyWith(clearError: true);
      expect(updated.error, isNull);
    });

    test('copyWith preserves error when not cleared', () {
      const base = KnowledgeState(error: 'bad');
      final updated = base.copyWith(isLoading: true);
      expect(updated.error, 'bad');
    });
  });

  // ---------------------------------------------------------------------------
  // MemoryExplorerState
  // ---------------------------------------------------------------------------
  group('MemoryExplorerState', () {
    final rec = MemoryRecord(
      id: 'm1',
      entityId: 'e1',
      entityType: 'fact',
      content: 'c',
      createdAt: DateTime.utc(2026),
    );

    test('default values', () {
      const s = MemoryExplorerState();
      expect(s.loading, false);
      expect(s.facts, isEmpty);
      expect(s.decisions, isEmpty);
      expect(s.entities, isEmpty);
      expect(s.timeline, isEmpty);
      expect(s.error, isNull);
    });

    test('copyWith replaces specified fields', () {
      const base = MemoryExplorerState();
      final updated = base.copyWith(
        loading: true,
        facts: [rec],
        decisions: [rec],
        entities: [rec],
        timeline: [rec],
      );
      expect(updated.loading, true);
      expect(updated.facts, hasLength(1));
      expect(updated.decisions, hasLength(1));
      expect(updated.entities, hasLength(1));
      expect(updated.timeline, hasLength(1));
    });

    test('copyWith without error arg drops previous error', () {
      const base = MemoryExplorerState(error: 'previous');
      final updated = base.copyWith(loading: true);
      // Implementation: `error: error` — so unspecified means null.
      expect(updated.error, isNull);
    });

    test('copyWith with explicit error sets it', () {
      const base = MemoryExplorerState();
      final updated = base.copyWith(error: 'boom');
      expect(updated.error, 'boom');
    });
  });
}
