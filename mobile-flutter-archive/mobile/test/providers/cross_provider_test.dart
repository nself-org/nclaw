// Cross-provider integration tests — exercise notifiers that depend on
// connectionProvider by running in real ProviderContainers seeded with
// empty SecureStorage (no servers paired).
//
// Single shared container per group to avoid sqflite close/reopen races
// across iterations — the ActionQueueService is a singleton.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nself_claw/providers/knowledge_provider.dart';
import 'package:nself_claw/providers/memory_explorer_provider.dart';
import 'package:nself_claw/providers/topic_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        if (call.method == 'read') return null;
        if (call.method == 'readAll') return <String, String>{};
        return null;
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method.startsWith('getApplicationDocuments')) {
          return '/tmp/nclaw-test-docs';
        }
        if (call.method.startsWith('getApplicationSupport')) {
          return '/tmp/nclaw-test-support';
        }
        if (call.method.startsWith('getTemporary')) {
          return '/tmp/nclaw-test-tmp';
        }
        return '/tmp/nclaw-test';
      },
    );
  });

  // Single container for the whole file — avoids sqflite close/reopen races
  // between tests.
  late ProviderContainer c;
  setUpAll(() {
    c = ProviderContainer();
  });

  tearDownAll(() {
    c.dispose();
  });

  // ---------------------------------------------------------------------------
  // KnowledgeNotifier
  // ---------------------------------------------------------------------------
  group('KnowledgeNotifier (no server)', () {
    test('initial state is empty and error-free', () {
      final state = c.read(knowledgeProvider);
      expect(state.isLoading, false);
      expect(state.results, isEmpty);
    });

    test('search without server sets error', () async {
      await c.read(knowledgeProvider.notifier).search('init');
      expect(c.read(knowledgeProvider).error, 'No server connected');
    });

    test('clearResults resets the state', () async {
      await c.read(knowledgeProvider.notifier).search('x');
      c.read(knowledgeProvider.notifier).clearResults();
      expect(c.read(knowledgeProvider).error, isNull);
      expect(c.read(knowledgeProvider).query, isNull);
    });

    test('getVersionInfo is null with no server', () async {
      expect(
          await c.read(knowledgeProvider.notifier).getVersionInfo(), isNull);
    });

    test('getCategories is empty with no server', () async {
      expect(
          await c.read(knowledgeProvider.notifier).getCategories(), isEmpty);
    });

    test('addNote returns false with no server', () async {
      expect(
          await c.read(knowledgeProvider.notifier).addNote('c', 'n'), false);
    });

    test('deleteNote returns false with no server', () async {
      expect(await c.read(knowledgeProvider.notifier).deleteNote('n'), false);
    });

    test('getNotes returns empty with no server', () async {
      expect(await c.read(knowledgeProvider.notifier).getNotes(), isEmpty);
    });

    test('getNotes with chunkId filter returns empty with no server',
        () async {
      expect(
        await c.read(knowledgeProvider.notifier).getNotes(chunkId: 'c'),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // MemoryExplorerNotifier
  // ---------------------------------------------------------------------------
  group('MemoryExplorerNotifier (no server)', () {
    test('initial state after auto-load remains default', () {
      final state = c.read(memoryExplorerProvider);
      expect(state.facts, isEmpty);
      expect(state.decisions, isEmpty);
      expect(state.entities, isEmpty);
      expect(state.timeline, isEmpty);
      expect(state.loading, false);
    });

    test('explicit loadAll is a no-op without server', () async {
      await c.read(memoryExplorerProvider.notifier).loadAll();
      expect(c.read(memoryExplorerProvider).loading, false);
      expect(c.read(memoryExplorerProvider).error, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // TopicTreeNotifier
  // ---------------------------------------------------------------------------
  group('TopicTreeNotifier (no server)', () {
    test('initial state is empty without loading', () {
      final state = c.read(topicTreeProvider);
      expect(state.loading, false);
      expect(state.topics, isEmpty);
      expect(state.error, isNull);
    });

    test('selectTopic updates selectedTopicId', () {
      c.read(topicTreeProvider.notifier).selectTopic('topic-1');
      expect(c.read(topicTreeProvider).selectedTopicId, 'topic-1');
    });

    test('toggleExpanded on non-existent topic is a no-op', () {
      c.read(topicTreeProvider.notifier).toggleExpanded('nope');
      expect(c.read(topicTreeProvider).topics, isEmpty);
    });

    test('loadTopics without server is a no-op', () async {
      await c.read(topicTreeProvider.notifier).loadTopics();
      expect(c.read(topicTreeProvider).topics, isEmpty);
    });

    test('reorderTopic without server is a no-op', () async {
      await c.read(topicTreeProvider.notifier).reorderTopic(
            topicId: 't1',
            newParentId: null,
            newSortOrder: 0,
          );
      expect(c.read(topicTreeProvider).topics, isEmpty);
    });

    test('createTopic without server is a no-op', () async {
      await c
          .read(topicTreeProvider.notifier)
          .createTopic(name: 'Work', color: '#000', icon: 'folder');
      expect(c.read(topicTreeProvider).topics, isEmpty);
    });

    test('updateTopic without server is a no-op', () async {
      await c.read(topicTreeProvider.notifier).updateTopic(
            topicId: 't1',
            name: 'New name',
            color: '#fff',
          );
      expect(c.read(topicTreeProvider).topics, isEmpty);
    });
  });
}
