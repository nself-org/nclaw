// Unit tests for ClawClient surface that doesn't require a real WebSocket
// (status getters, disconnect when not connected, send while disconnected,
// dispose).

import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/services/claw_client.dart';

void main() {
  group('ClawClient basic surface', () {
    test('initial status is disconnected', () {
      final c = ClawClient();
      expect(c.status, ClawConnectionStatus.disconnected);
      c.dispose();
    });

    test('send() while disconnected silently no-ops', () {
      final c = ClawClient();
      // No throw
      c.send(const {'type': 'ping'});
      c.dispose();
    });

    test('messages stream is a broadcast stream ready to listen', () {
      final c = ClawClient();
      expect(c.messages.isBroadcast, true);
      c.dispose();
    });

    test('statusStream is a broadcast stream ready to listen', () {
      final c = ClawClient();
      expect(c.statusStream.isBroadcast, true);
      c.dispose();
    });

    test('actions stream is a broadcast stream ready to listen', () {
      final c = ClawClient();
      expect(c.actions.isBroadcast, true);
      c.dispose();
    });

    test('disconnect() while not connected is idempotent', () async {
      final c = ClawClient();
      await c.disconnect();
      expect(c.status, ClawConnectionStatus.disconnected);
      c.dispose();
    });

    test('dispose() closes without throwing', () async {
      final c = ClawClient();
      await c.dispose();
      // After dispose, streams are closed; status stays disconnected.
      expect(c.status, ClawConnectionStatus.disconnected);
    });
  });

  group('ClawConnectionStatus enum', () {
    test('has four values', () {
      expect(ClawConnectionStatus.values, hasLength(4));
      expect(ClawConnectionStatus.disconnected.name, 'disconnected');
      expect(ClawConnectionStatus.connecting.name, 'connecting');
      expect(ClawConnectionStatus.connected.name, 'connected');
      expect(ClawConnectionStatus.error.name, 'error');
    });
  });
}
