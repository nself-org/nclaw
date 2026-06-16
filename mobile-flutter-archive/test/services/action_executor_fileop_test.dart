// Tests for ActionExecutorService file operations. Uses the real filesystem
// via a mocked path_provider pointing to a per-test temp directory.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/models/claw_action.dart';
import 'package:nself_claw/services/action_executor_service.dart';

ClawAction _fileOp({
  required Map<String, dynamic> params,
  DateTime? createdAt,
  DateTime? expiresAt,
}) {
  final now = DateTime.now();
  return ClawAction(
    id: 'a-${now.microsecondsSinceEpoch}',
    sessionId: 's',
    type: ActionType.fileOp,
    params: params,
    status: ActionStatus.pending,
    createdAt: createdAt ?? now,
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sandbox = Directory.systemTemp
      .createTempSync('nclaw-executor-')
      .path;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => sandbox,
    );
  });

  tearDownAll(() {
    try {
      Directory(sandbox).deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ActionExecutorService._executeFileOp', () {
    final svc = ActionExecutorService();

    test('missing path returns error', () async {
      final res = await svc.execute(_fileOp(params: const {'op': 'read'}));
      expect(res['error'], contains('missing path'));
    });

    test('write + read round-trips content', () async {
      final write = await svc.execute(_fileOp(params: const {
        'op': 'write',
        'path': 'hello.txt',
        'content': 'world',
      }));
      expect(write['written'], true);
      expect(write['bytes'], 5);

      final read = await svc.execute(_fileOp(params: const {
        'op': 'read',
        'path': 'hello.txt',
      }));
      expect(read['content'], 'world');
    });

    test('read of missing file returns error', () async {
      final res = await svc.execute(_fileOp(params: const {
        'op': 'read',
        'path': 'does-not-exist.txt',
      }));
      expect(res['error'], contains('file not found'));
    });

    test('list of directory returns entries', () async {
      await svc.execute(_fileOp(params: const {
        'op': 'write',
        'path': 'listme/a.txt',
        'content': 'a',
      }));
      await svc.execute(_fileOp(params: const {
        'op': 'write',
        'path': 'listme/b.txt',
        'content': 'b',
      }));
      final res = await svc.execute(_fileOp(params: const {
        'op': 'list',
        'path': 'listme',
      }));
      expect(res['count'], 2);
      expect((res['entries'] as List).length, 2);
    });

    test('list of missing directory returns error', () async {
      final res = await svc.execute(_fileOp(params: const {
        'op': 'list',
        'path': 'ghost-dir-42',
      }));
      expect(res['error'], contains('directory not found'));
    });

    test('delete removes an existing file', () async {
      await svc.execute(_fileOp(params: const {
        'op': 'write',
        'path': 'trash.txt',
        'content': 'x',
      }));
      final del = await svc.execute(_fileOp(params: const {
        'op': 'delete',
        'path': 'trash.txt',
      }));
      expect(del['deleted'], true);
      final read = await svc.execute(_fileOp(params: const {
        'op': 'read',
        'path': 'trash.txt',
      }));
      expect(read['error'], contains('file not found'));
    });

    test('delete of missing file returns error', () async {
      final res = await svc.execute(_fileOp(params: const {
        'op': 'delete',
        'path': 'nope-xyz.txt',
      }));
      expect(res['error'], contains('file not found'));
    });

    test('unknown op returns error', () async {
      final res = await svc.execute(_fileOp(params: const {
        'op': 'weird',
        'path': 'x.txt',
      }));
      expect(res['error'], contains('unknown fileOp'));
    });
  });

  group('ActionExecutorService._executeBrowser param validation', () {
    final svc = ActionExecutorService();

    test('missing url returns error', () async {
      final res = await svc.execute(ClawAction(
        id: 'b1',
        sessionId: 's',
        type: ActionType.browser,
        params: const {},
        status: ActionStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ));
      expect(res['error'], contains('missing url'));
    });
  });

  group('ActionExecutorService._executeOAuth param validation', () {
    final svc = ActionExecutorService();

    test('missing url returns error', () async {
      final res = await svc.execute(ClawAction(
        id: 'o1',
        sessionId: 's',
        type: ActionType.oauth,
        params: const {'provider': 'google'},
        status: ActionStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ));
      expect(res['error'], contains('missing url'));
    });
  });
}
