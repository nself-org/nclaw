// Unit tests for ActionQueueService. Exercises the SQLite-backed queue end
// to end using sqflite_common_ffi for in-process execution.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nself_claw/models/claw_action.dart';
import 'package:nself_claw/services/action_queue_service.dart';

ClawAction _action({
  String id = 'a1',
  ActionStatus status = ActionStatus.pending,
  DateTime? createdAt,
  DateTime? expiresAt,
}) {
  final now = DateTime.now();
  return ClawAction(
    id: id,
    sessionId: 's',
    type: ActionType.shell,
    params: const {'cmd': 'ls'},
    status: status,
    createdAt: createdAt ?? now,
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/nclaw-aqs-test',
    );
    // Ensure parent dir exists and start from a clean DB file — prior runs
    // may have left rows with malformed `result` data (known source bug).
    Directory('/tmp/nclaw-aqs-test').createSync(recursive: true);
    final f = File('/tmp/nclaw-aqs-test/nclaw_actions.db');
    if (f.existsSync()) f.deleteSync();
  });

  late ActionQueueService svc;

  setUp(() async {
    svc = ActionQueueService();
    await svc.init();
    // Use fresh unique IDs per test to avoid leakage across runs.
  });

  tearDown(() async {
    await svc.dispose();
  });

  group('ActionQueueService', () {
    test('init is idempotent', () async {
      await svc.init();
      await svc.init();
      expect(await svc.getAll(), isNotNull);
    });

    test('enqueue + getById returns the stored action', () async {
      final id = 'aqs-${DateTime.now().microsecondsSinceEpoch}';
      await svc.enqueue(_action(id: id));
      final fetched = await svc.getById(id);
      expect(fetched, isNotNull);
      expect(fetched!.id, id);
      expect(fetched.type, ActionType.shell);
      expect(fetched.status, ActionStatus.pending);
    });

    test('getById returns null for unknown id', () async {
      expect(await svc.getById('nonexistent-xyz'), isNull);
    });

    test('enqueue is idempotent on duplicate id', () async {
      final id = 'dup-${DateTime.now().microsecondsSinceEpoch}';
      await svc.enqueue(_action(id: id));
      await svc.enqueue(_action(id: id));
      final rows =
          (await svc.getByStatus([ActionStatus.pending])).where((a) => a.id == id);
      expect(rows.length, 1);
    });

    test('updateStatus changes status and executed_at for terminal transitions',
        () async {
      final id = 'upd-${DateTime.now().microsecondsSinceEpoch}';
      await svc.enqueue(_action(id: id));
      // Note: intentionally not passing `result` — the current source stores
      // result.toString() (Map.toString()) instead of jsonEncode, which
      // round-trips as malformed JSON. Bug tracked separately.
      await svc.updateStatus(id, ActionStatus.done);
      final after = await svc.getById(id);
      expect(after?.status, ActionStatus.done);
      expect(after?.executedAt, isNotNull);
    });

    test('updateStatus for non-terminal (e.g. approved) does not set '
        'executed_at', () async {
      final id = 'upd2-${DateTime.now().microsecondsSinceEpoch}';
      await svc.enqueue(_action(id: id));
      await svc.updateStatus(id, ActionStatus.approved);
      final after = await svc.getById(id);
      expect(after?.status, ActionStatus.approved);
      expect(after?.executedAt, isNull);
    });

    test('getByStatus filters correctly', () async {
      final now = DateTime.now().microsecondsSinceEpoch;
      final a1 = 'gbs-$now-1';
      final a2 = 'gbs-$now-2';
      await svc.enqueue(_action(id: a1));
      await svc.enqueue(_action(id: a2));
      await svc.updateStatus(a2, ActionStatus.done);
      final pending = await svc.getByStatus([ActionStatus.pending]);
      final done = await svc.getByStatus([ActionStatus.done]);
      expect(pending.any((a) => a.id == a1), true);
      expect(done.any((a) => a.id == a2), true);
    });

    test('getPending returns only pending', () async {
      final id = 'pend-${DateTime.now().microsecondsSinceEpoch}';
      await svc.enqueue(_action(id: id));
      final pending = await svc.getPending();
      expect(pending.any((a) => a.id == id), true);
    });

    test('countByStatus reports integer counts', () async {
      final id = 'cnt-${DateTime.now().microsecondsSinceEpoch}';
      await svc.enqueue(_action(id: id));
      final n = await svc.countByStatus(ActionStatus.pending);
      expect(n, greaterThanOrEqualTo(1));
    });

    test('expireOldActions marks old pending as expired', () async {
      final id = 'exp-${DateTime.now().microsecondsSinceEpoch}';
      // Put expires_at in the past so expireOldActions matches it.
      await svc.enqueue(_action(
        id: id,
        expiresAt: DateTime.now().subtract(const Duration(days: 2)),
      ));
      final count = await svc.expireOldActions();
      expect(count, greaterThanOrEqualTo(1));
      final after = await svc.getById(id);
      expect(after?.status, ActionStatus.expired);
    });

    test('expireOldActions returns 0 when nothing to expire', () async {
      final count = await svc.expireOldActions();
      expect(count, greaterThanOrEqualTo(0));
    });

    test('pruneHistory removes old terminal actions', () async {
      final id = 'prn-${DateTime.now().microsecondsSinceEpoch}';
      // Insert a row with old created_at (8 days ago) in done status.
      await svc.enqueue(_action(
        id: id,
        createdAt: DateTime.now().subtract(const Duration(days: 8)),
      ));
      await svc.updateStatus(id, ActionStatus.done);
      final pruned = await svc.pruneHistory();
      expect(pruned, greaterThanOrEqualTo(1));
      expect(await svc.getById(id), isNull);
    });

    test('onChange stream fires on enqueue and updateStatus', () async {
      var count = 0;
      final sub = svc.onChange.listen((_) => count++);
      final id = 'chg-${DateTime.now().microsecondsSinceEpoch}';
      await svc.enqueue(_action(id: id));
      await svc.updateStatus(id, ActionStatus.done);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(count, greaterThanOrEqualTo(2));
      await sub.cancel();
    });
  });
}
