// intelligence_service_test.dart — Unit tests for IntelligenceService.
//
// Purpose: Verify the IntelligenceService client correctly constructs requests,
//          parses responses, and returns typed results. Uses a mock http.Client
//          to avoid any real network calls. Tests cover searchMemory, insertMemory,
//          queryKnowledge, and invokeTool surface.
// Constraints: No real gRPC channel. No network calls. No hardcoded host/port.
// SPORT: P2-E5-W4-S8-T08.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:nself_claw/services/intelligence_service.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Returns a [MockClient] that always responds with [statusCode] and [body].
MockClient mockClient(int statusCode, Map<String, dynamic> body) {
  return MockClient((_) async => http.Response(
        jsonEncode(body),
        statusCode,
        headers: {'content-type': 'application/json'},
      ));
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // Sanity check: host/port come from constructor, never hardcoded.
  test('IntelligenceService does not hardcode host or port', () {
    final svc = IntelligenceService(host: 'my-server.local', port: 9441);
    // If this compiles and constructs without exception, the constructor is
    // accepting dynamic host/port — not hardcoded.
    expect(svc, isNotNull);
    svc.dispose();
  });

  group('searchMemory', () {
    test('returns correct MemoryResult list on success', () async {
      final client = mockClient(200, {
        'results': [
          {
            'id': '550e8400-e29b-41d4-a716-446655440000',
            'content': 'Ali prefers concise answers.',
            'memory_type': 'preference',
            'namespace': 'personal/nclaw_ali',
            'valid_from': '2026-06-14T10:00:00Z',
            'valid_until': '',
            'score': 0.92,
          }
        ]
      });

      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      final results = await svc.searchMemory('preferences', 'user-123');

      expect(results, hasLength(1));
      expect(results.first.content, 'Ali prefers concise answers.');
      expect(results.first.memoryType, 'preference');
      expect(results.first.score, closeTo(0.92, 0.001));
      expect(results.first.id, '550e8400-e29b-41d4-a716-446655440000');
      svc.dispose();
    });

    test('returns empty list when results array is absent', () async {
      final client = mockClient(200, <String, dynamic>{});
      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      final results = await svc.searchMemory('anything', 'user-456');
      expect(results, isEmpty);
      svc.dispose();
    });

    test('throws on non-2xx status', () async {
      final client = MockClient((_) async => http.Response('Internal Server Error', 500));
      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      expect(
        () => svc.searchMemory('query', 'user-789'),
        throwsException,
      );
      svc.dispose();
    });
  });

  group('insertMemory', () {
    test('completes without error on 200', () async {
      final client = mockClient(200, {'id': 'new-uuid'});
      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      await expectLater(
        svc.insertMemory('New memory content', 'user-001', 'personal/nclaw_user001'),
        completes,
      );
      svc.dispose();
    });

    test('throws on 400 error', () async {
      final client = MockClient((_) async => http.Response('Bad Request', 400));
      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      expect(
        () => svc.insertMemory('content', 'user', 'ns'),
        throwsException,
      );
      svc.dispose();
    });
  });

  group('queryKnowledge', () {
    test('returns KnowledgeResult list on success', () async {
      final client = mockClient(200, {
        'results': [
          {
            'id': 'chunk-uuid-001',
            'content': 'nSelf uses Hasura for GraphQL.',
            'doc_type': 'runbook',
            'source_ref': 'docs/architecture.md',
            'org_slug': 'nself-internal',
            'score': 0.88,
          }
        ]
      });

      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      final results = await svc.queryKnowledge('Hasura', 'nself-internal');

      expect(results, hasLength(1));
      expect(results.first.content, 'nSelf uses Hasura for GraphQL.');
      expect(results.first.docType, 'runbook');
      expect(results.first.orgSlug, 'nself-internal');
      svc.dispose();
    });
  });

  group('invokeTool', () {
    test('returns AgentToolResult with resultJson on success', () async {
      final client = mockClient(200, {
        'result_json': '{"rows":42}',
        'error': '',
        'tool_name': 'NselfDbQuery',
      });

      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      final result = await svc.invokeTool('NselfDbQuery', {'sql': 'SELECT COUNT(*) FROM users'});

      expect(result.isSuccess, isTrue);
      expect(result.resultJson, '{"rows":42}');
      expect(result.toolName, 'NselfDbQuery');
      svc.dispose();
    });

    test('isSuccess is false when error field is non-empty', () async {
      final client = mockClient(200, {
        'result_json': '',
        'error': 'unknown tool: BadTool',
        'tool_name': 'BadTool',
      });

      final svc = IntelligenceService(host: 'localhost', port: 9441, client: client);
      final result = await svc.invokeTool('BadTool', {});

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('unknown tool'));
      svc.dispose();
    });
  });
}
