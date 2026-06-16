// Integration tests for ConnectionNotifier. Uses a fake ClawClient and
// bypassed SecureStorage / ActionQueue so the notifier can be tested without
// hitting WebSocket or SQLite.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:nself_claw/models/server_config.dart';
import 'package:nself_claw/providers/connection_provider.dart';
import 'package:nself_claw/services/agent_queue_api_client.dart';
import 'package:nself_claw/services/claw_client.dart';

// A ClawClient stub that records calls and never opens a real socket.
class _FakeClawClient implements ClawClient {
  int connectCalls = 0;
  int disconnectCalls = 0;
  int disposeCalls = 0;
  final _statusController =
      StreamController<ClawConnectionStatus>.broadcast();
  final _actionsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  ClawConnectionStatus get status => ClawConnectionStatus.disconnected;

  @override
  Stream<ClawConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _messagesController.stream;

  // actions stream is only required if ConnectionNotifier._listenForActions
  // subscribes — it does. Provide a broadcast controller so the subscription
  // succeeds.
  Stream<Map<String, dynamic>> get actions => _actionsController.stream;

  @override
  Future<void> connect({
    required String serverUrl,
    String? jwtToken,
  }) async {
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  void send(Map<String, dynamic> message) {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _statusController.close();
    await _actionsController.close();
    await _messagesController.close();
  }

  // Unreferenced ClawClient members — fall through to noSuchMethod where
  // possible.
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final args = call.arguments as Map?;
        final key = args?['key'] as String?;
        switch (call.method) {
          case 'read':
            return key != null ? store[key] : null;
          case 'write':
            final value = args!['value'] as String?;
            if (key != null) {
              if (value == null) {
                store.remove(key);
              } else {
                store[key] = value;
              }
            }
            return null;
          case 'delete':
            if (key != null) store.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.from(store);
          case 'deleteAll':
            store.clear();
            return null;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('ConnectionNotifier', () {
    test('starts with empty state', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      // Wait for _loadSaved to complete.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(n.state.servers, isEmpty);
      expect(n.state.activeServerId, isNull);
      expect(n.state.hasPairedServers, false);
      n.dispose();
    });

    test('addServer persists and triggers connect', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      const server = ServerConfig(
        id: 's1',
        url: 'https://example.com',
        name: 'Example',
        jwtToken: 'jwt',
      );
      await n.addServer(server);
      expect(n.state.servers, hasLength(1));
      expect(n.state.activeServerId, 's1');
      expect(fake.connectCalls, greaterThanOrEqualTo(1));
      // Storage should now contain the encoded list.
      expect(store[StorageKeys.servers], isNotNull);
      n.dispose();
    });

    test('addServer replaces existing with same id', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 's1', url: 'a', name: 'A'));
      await n.addServer(const ServerConfig(id: 's1', url: 'b', name: 'B'));
      expect(n.state.servers, hasLength(1));
      expect(n.state.servers.first.url, 'b');
      n.dispose();
    });

    test('updateToken replaces jwt for a specific server', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(
          id: 's1', url: 'https://x', name: 'X', jwtToken: 'old'));
      await n.updateToken('s1', 'new-jwt', refreshToken: 'r');
      final s = n.state.servers.firstWhere((s) => s.id == 's1');
      expect(s.jwtToken, 'new-jwt');
      expect(s.refreshToken, 'r');
      n.dispose();
    });

    test('switchServer switches active and triggers connect', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 'a', url: 'ua', name: 'A'));
      await n.addServer(const ServerConfig(id: 'b', url: 'ub', name: 'B'));
      fake.connectCalls = 0;
      await n.switchServer('a');
      expect(n.state.activeServerId, 'a');
      expect(fake.connectCalls, greaterThanOrEqualTo(1));
      n.dispose();
    });

    test('switchServer with unknown id is a no-op', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 'a', url: 'ua', name: 'A'));
      fake.connectCalls = 0;
      await n.switchServer('ghost');
      expect(n.state.activeServerId, 'a');
      expect(fake.connectCalls, 0);
      n.dispose();
    });

    test('removeServer of active server drops active and connects to next',
        () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 'a', url: 'ua', name: 'A'));
      await n.addServer(const ServerConfig(id: 'b', url: 'ub', name: 'B'));
      // b is now active. Remove b.
      await n.removeServer('b');
      expect(n.state.servers, hasLength(1));
      expect(n.state.servers.first.id, 'a');
      expect(n.state.activeServerId, 'a');
      n.dispose();
    });

    test('removeServer of only server clears active', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 'a', url: 'ua', name: 'A'));
      await n.removeServer('a');
      expect(n.state.servers, isEmpty);
      expect(n.state.activeServerId, isNull);
      expect(n.state.status, ConnectionStatus.disconnected);
      n.dispose();
    });

    test('removeServer of non-active server preserves active', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 'a', url: 'ua', name: 'A'));
      await n.addServer(const ServerConfig(id: 'b', url: 'ub', name: 'B'));
      // b is active; remove a.
      await n.removeServer('a');
      expect(n.state.activeServerId, 'b');
      n.dispose();
    });

    test('unpairAll clears state and storage', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 'a', url: 'ua', name: 'A'));
      await n.unpairAll();
      expect(n.state.servers, isEmpty);
      expect(n.state.activeServerId, isNull);
      expect(store[StorageKeys.servers], isNull);
      n.dispose();
    });

    test('reconnect with no active server is a no-op', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      fake.connectCalls = 0;
      await n.reconnect();
      expect(fake.connectCalls, 0);
      n.dispose();
    });

    test('reconnect with active server triggers disconnect+connect', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(const ServerConfig(id: 'a', url: 'ua', name: 'A'));
      final before = fake.connectCalls;
      await n.reconnect();
      expect(fake.connectCalls, greaterThan(before));
      expect(fake.disconnectCalls, greaterThanOrEqualTo(1));
      n.dispose();
    });

    test('client getter returns the underlying client', () async {
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(client: fake as ClawClient);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(identical(n.client, fake), true);
      n.dispose();
    });

    test('agent queue drain exception path is safe', () async {
      final agentClient = AgentQueueApiClient(
        httpClient: MockClient((_) async => throw Exception('network down')),
      );
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(
        client: fake as ClawClient,
        agentQueueClient: agentClient,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(
        const ServerConfig(id: 's', url: 'https://x', name: 'S'),
      );
      // Emit a connected status — triggers _drainQueue which will catch the
      // MockClient exception and log debugPrint without throwing.
      fake._statusController.add(ClawConnectionStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.status, ConnectionStatus.connected);
      n.dispose();
    });

    test('status stream translates all ClawConnectionStatus values', () async {
      final agentClient = AgentQueueApiClient(
        httpClient:
            MockClient((_) async => http.Response('{"actions":[]}', 200)),
      );
      final fake = _FakeClawClient();
      final n = ConnectionNotifier(
        client: fake as ClawClient,
        agentQueueClient: agentClient,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await n.addServer(
        const ServerConfig(id: 's', url: 'https://x', name: 'S'),
      );
      fake._statusController.add(ClawConnectionStatus.connecting);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(n.state.status, ConnectionStatus.connecting);

      fake._statusController.add(ClawConnectionStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state.status, ConnectionStatus.connected);

      fake._statusController.add(ClawConnectionStatus.error);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(n.state.status, ConnectionStatus.error);

      fake._statusController.add(ClawConnectionStatus.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(n.state.status, ConnectionStatus.disconnected);

      n.dispose();
    });
  });
}
