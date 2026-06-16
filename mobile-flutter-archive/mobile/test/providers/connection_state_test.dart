// Unit tests for ConnectionState — the pure Riverpod state class from
// connection_provider.dart. ConnectionNotifier itself needs real services;
// the state class exercises without any platform channels.

import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/models/server_config.dart';
import 'package:nself_claw/providers/connection_provider.dart';

void main() {
  group('StorageKeys', () {
    test('has stable keys', () {
      expect(StorageKeys.servers, 'nclaw_servers');
      expect(StorageKeys.activeServerId, 'nclaw_active_server_id');
    });
  });

  group('ConnectionStatus enum', () {
    test('has four values', () {
      expect(ConnectionStatus.values, hasLength(4));
      expect(ConnectionStatus.disconnected.name, 'disconnected');
      expect(ConnectionStatus.connecting.name, 'connecting');
      expect(ConnectionStatus.connected.name, 'connected');
      expect(ConnectionStatus.error.name, 'error');
    });
  });

  group('ConnectionState', () {
    test('default constructor', () {
      const s = ConnectionState();
      expect(s.servers, isEmpty);
      expect(s.activeServerId, isNull);
      expect(s.status, ConnectionStatus.disconnected);
      expect(s.errorMessage, isNull);
      expect(s.activeServer, isNull);
      expect(s.hasPairedServers, false);
    });

    test('hasPairedServers true when servers non-empty', () {
      const s = ConnectionState(
        servers: [ServerConfig(id: 's1', url: 'u', name: 'n')],
      );
      expect(s.hasPairedServers, true);
    });

    test('activeServer returns matching server by id', () {
      const s = ConnectionState(
        servers: [
          ServerConfig(id: 'a', url: 'ua', name: 'A'),
          ServerConfig(id: 'b', url: 'ub', name: 'B'),
        ],
        activeServerId: 'b',
      );
      expect(s.activeServer?.id, 'b');
      expect(s.activeServer?.name, 'B');
    });

    test('activeServer returns null when id not found', () {
      const s = ConnectionState(
        servers: [ServerConfig(id: 'a', url: 'ua', name: 'A')],
        activeServerId: 'ghost',
      );
      expect(s.activeServer, isNull);
    });

    test('activeServer returns null when activeServerId is null', () {
      const s = ConnectionState(
        servers: [ServerConfig(id: 'a', url: 'ua', name: 'A')],
      );
      expect(s.activeServer, isNull);
    });

    test('copyWith replaces specified fields, preserves others', () {
      const base = ConnectionState(
        servers: [ServerConfig(id: 'a', url: 'u', name: 'n')],
        activeServerId: 'a',
        status: ConnectionStatus.connecting,
        errorMessage: 'initial',
      );
      final updated = base.copyWith(status: ConnectionStatus.connected);
      expect(updated.status, ConnectionStatus.connected);
      expect(updated.servers, hasLength(1));
      expect(updated.activeServerId, 'a');
      expect(updated.errorMessage, 'initial');
    });

    test('copyWith clearError drops errorMessage', () {
      const base = ConnectionState(errorMessage: 'bad');
      final updated = base.copyWith(clearError: true);
      expect(updated.errorMessage, isNull);
    });

    test('copyWith clearActiveServer drops activeServerId', () {
      const base = ConnectionState(activeServerId: 'a');
      final updated = base.copyWith(clearActiveServer: true);
      expect(updated.activeServerId, isNull);
    });

    test('copyWith replaces servers list when provided', () {
      const base = ConnectionState();
      final updated = base.copyWith(
        servers: const [ServerConfig(id: 'x', url: 'u', name: 'n')],
      );
      expect(updated.servers, hasLength(1));
      expect(updated.servers.first.id, 'x');
    });
  });
}
