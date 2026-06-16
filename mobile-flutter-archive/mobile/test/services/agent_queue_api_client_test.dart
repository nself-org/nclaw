// Unit tests for AgentQueueApiClient using http MockClient.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:nself_claw/services/agent_queue_api_client.dart';

void main() {
  group('AgentQueueApiClient.drainQueue', () {
    test('returns parsed list on 200', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/claw/queue/drain');
        expect(request.url.queryParameters['namespace'], 'claw');
        expect(request.headers['Authorization'], 'Bearer jwt-abc');
        return http.Response(
          jsonEncode({
            'actions': [
              {
                'id': 'q1',
                'namespace': 'claw',
                'action': 'notify',
                'status': 'pending',
                'payload': {'k': 'v'},
                'created_at': '2026-04-20T00:00:00.000Z',
                'expires_at': '2026-04-21T00:00:00.000Z',
              }
            ]
          }),
          200,
        );
      });
      final api = AgentQueueApiClient(httpClient: client);
      final actions = await api.drainQueue(
        serverUrl: 'https://api.example.com',
        namespace: 'claw',
        jwtToken: 'jwt-abc',
      );
      expect(actions, hasLength(1));
      expect(actions.first.id, 'q1');
      expect(actions.first.action, 'notify');
    });

    test('returns empty list when body has no actions key', () async {
      final client =
          MockClient((_) async => http.Response(jsonEncode({}), 200));
      final api = AgentQueueApiClient(httpClient: client);
      final actions = await api.drainQueue(
        serverUrl: 'https://x',
        namespace: 'claw',
      );
      expect(actions, isEmpty);
    });

    test('omits Authorization header when jwtToken is null or empty',
        () async {
      final client = MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), false);
        return http.Response(jsonEncode({'actions': []}), 200);
      });
      final api = AgentQueueApiClient(httpClient: client);
      await api.drainQueue(serverUrl: 'https://x', namespace: 'claw');
      await api.drainQueue(
          serverUrl: 'https://x', namespace: 'claw', jwtToken: '');
    });

    test('throws AgentQueueException on non-200', () async {
      final client = MockClient((_) async => http.Response('Server Error', 500));
      final api = AgentQueueApiClient(httpClient: client);
      try {
        await api.drainQueue(serverUrl: 'https://x', namespace: 'claw');
        fail('should have thrown');
      } on AgentQueueException catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, contains('drain failed'));
        expect(e.toString(), contains('drain failed'));
      }
    });
  });

  group('AgentQueueApiClient.acknowledgeAction', () {
    test('succeeds on 200 and sends result body', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/claw/queue/ack/action-1');
        expect(request.headers['Content-Type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['result'], {'ok': true});
        return http.Response('', 200);
      });
      final api = AgentQueueApiClient(httpClient: client);
      await api.acknowledgeAction(
        serverUrl: 'https://x',
        actionId: 'action-1',
        result: const {'ok': true},
      );
    });

    test('succeeds on 201', () async {
      final client = MockClient((_) async => http.Response('', 201));
      final api = AgentQueueApiClient(httpClient: client);
      await api.acknowledgeAction(
        serverUrl: 'https://x',
        actionId: 'a',
      );
      // no exception
    });

    test('sends empty body when result is null', () async {
      final client = MockClient((request) async {
        expect(request.body, '{}');
        return http.Response('', 200);
      });
      final api = AgentQueueApiClient(httpClient: client);
      await api.acknowledgeAction(
        serverUrl: 'https://x',
        actionId: 'a',
      );
    });

    test('throws on non-2xx', () async {
      final client = MockClient((_) async => http.Response('nope', 403));
      final api = AgentQueueApiClient(httpClient: client);
      try {
        await api.acknowledgeAction(
            serverUrl: 'https://x', actionId: 'a');
        fail('should have thrown');
      } on AgentQueueException catch (e) {
        expect(e.statusCode, 403);
        expect(e.message, contains('ack failed'));
      }
    });

    test('includes Authorization header when jwtToken is provided', () async {
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer my-jwt');
        return http.Response('', 200);
      });
      final api = AgentQueueApiClient(httpClient: client);
      await api.acknowledgeAction(
        serverUrl: 'https://x',
        actionId: 'a',
        jwtToken: 'my-jwt',
      );
    });
  });

  group('AgentQueueException', () {
    test('toString returns message', () {
      const e = AgentQueueException('boom', statusCode: 418);
      expect(e.toString(), 'boom');
      expect(e.statusCode, 418);
    });
  });
}
