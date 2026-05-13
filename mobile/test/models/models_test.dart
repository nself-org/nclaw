// Unit tests for data-class models. Pure Dart — no Flutter widget tree needed.
// Targets: app_settings, topic_node, queued_action, server_config,
// memory_record, claw_action. These are serializer-heavy classes with high
// line-count and zero platform dependencies — ideal for coverage ROI.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nself_claw/models/app_settings.dart';
import 'package:nself_claw/models/claw_action.dart';
import 'package:nself_claw/models/memory_record.dart';
import 'package:nself_claw/models/queued_action.dart';
import 'package:nself_claw/models/server_config.dart';
import 'package:nself_claw/models/topic_node.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AppSettings
  // ---------------------------------------------------------------------------
  group('AppSettings', () {
    test('default constructor sets documented defaults', () {
      const s = AppSettings();
      expect(s.displayName, '');
      expect(s.language, 'en');
      expect(s.defaultModel, 'auto');
      expect(s.temperature, 0.7);
      expect(s.maxTokens, 4096);
      expect(s.theme, 'system');
      expect(s.fontSize, 14.0);
      expect(s.compactMode, false);
      expect(s.pushEnabled, true);
      expect(s.soundEnabled, true);
      expect(s.digestEnabled, true);
      expect(s.digestFrequency, 'daily');
      expect(s.biometricLock, false);
      expect(s.autoLockMinutes, 5);
      expect(s.offlineModeEnabled, true);
      expect(s.cacheSizeMb, 100);
      expect(s.autoSync, true);
      expect(s.syncIntervalMinutes, 15);
      expect(s.defaultShareTopic, '');
      expect(s.shareSheetEnabled, true);
      expect(s.apiKeys, isEmpty);
      expect(s.subscriptionTier, isNull);
      expect(s.subscriptionExpiry, isNull);
      expect(s.debugMode, false);
      expect(s.customEndpoint, isNull);
      expect(s.experimentalFeatures, false);
    });

    test('fromJson with empty map falls back to defaults', () {
      final s = AppSettings.fromJson({});
      expect(s.displayName, '');
      expect(s.language, 'en');
      expect(s.theme, 'system');
      expect(s.temperature, 0.7);
      expect(s.maxTokens, 4096);
      expect(s.apiKeys, isEmpty);
      expect(s.subscriptionExpiry, isNull);
      expect(s.customEndpoint, isNull);
    });

    test('fromJson parses all fields', () {
      final expiry = DateTime.utc(2030, 1, 1);
      final json = {
        'display_name': 'Ada',
        'bio': 'engineer',
        'avatar_url': 'https://example.com/a.png',
        'language': 'de',
        'launch_at_login': true,
        'default_model': 'gpt-4',
        'temperature': 0.2,
        'max_tokens': 8192,
        'theme': 'dark',
        'font_size': 16.0,
        'compact_mode': true,
        'push_enabled': false,
        'sound_enabled': false,
        'badge_enabled': false,
        'digest_enabled': false,
        'digest_frequency': 'weekly',
        'biometric_lock': true,
        'analytics_enabled': true,
        'auto_lock_minutes': 10,
        'offline_mode_enabled': false,
        'cache_size_mb': 250,
        'auto_sync': false,
        'sync_interval_minutes': 60,
        'default_share_topic': 'work',
        'share_sheet_enabled': false,
        'api_keys': {'openai': 'sk-abc'},
        'subscription_tier': 'pro',
        'subscription_expiry': expiry.toIso8601String(),
        'debug_mode': true,
        'custom_endpoint': 'https://api.example.com',
        'experimental_features': true,
      };
      final s = AppSettings.fromJson(json);
      expect(s.displayName, 'Ada');
      expect(s.bio, 'engineer');
      expect(s.language, 'de');
      expect(s.launchAtLogin, true);
      expect(s.defaultModel, 'gpt-4');
      expect(s.temperature, 0.2);
      expect(s.maxTokens, 8192);
      expect(s.theme, 'dark');
      expect(s.compactMode, true);
      expect(s.digestFrequency, 'weekly');
      expect(s.biometricLock, true);
      expect(s.autoLockMinutes, 10);
      expect(s.cacheSizeMb, 250);
      expect(s.syncIntervalMinutes, 60);
      expect(s.apiKeys['openai'], 'sk-abc');
      expect(s.subscriptionTier, 'pro');
      expect(s.subscriptionExpiry, expiry);
      expect(s.debugMode, true);
      expect(s.customEndpoint, 'https://api.example.com');
      expect(s.experimentalFeatures, true);
    });

    test('toJson -> fromJson round-trips', () {
      final original = const AppSettings(
        displayName: 'Ada',
        bio: 'eng',
        avatarUrl: 'x',
        language: 'fr',
        launchAtLogin: true,
        defaultModel: 'claude',
        temperature: 0.5,
        maxTokens: 2048,
        theme: 'light',
        fontSize: 12.0,
        compactMode: true,
        digestFrequency: 'never',
        biometricLock: true,
        autoLockMinutes: 15,
        cacheSizeMb: 500,
        syncIntervalMinutes: 30,
        apiKeys: {'k': 'v'},
        subscriptionTier: 'enterprise',
        debugMode: true,
        customEndpoint: 'x',
        experimentalFeatures: true,
      );
      final roundTripped = AppSettings.fromJson(original.toJson());
      expect(roundTripped.displayName, 'Ada');
      expect(roundTripped.language, 'fr');
      expect(roundTripped.defaultModel, 'claude');
      expect(roundTripped.temperature, 0.5);
      expect(roundTripped.maxTokens, 2048);
      expect(roundTripped.theme, 'light');
      expect(roundTripped.fontSize, 12.0);
      expect(roundTripped.digestFrequency, 'never');
      expect(roundTripped.subscriptionTier, 'enterprise');
    });

    test('copyWith replaces only provided fields', () {
      const s = AppSettings(displayName: 'A', theme: 'dark');
      final s2 = s.copyWith(displayName: 'B');
      expect(s2.displayName, 'B');
      expect(s2.theme, 'dark'); // preserved
      final s3 = s.copyWith(theme: 'light', fontSize: 18.0);
      expect(s3.theme, 'light');
      expect(s3.fontSize, 18.0);
      expect(s3.displayName, 'A');
    });

    test('copyWith preserves every default-set field when called empty', () {
      const s = AppSettings(
        temperature: 0.9,
        maxTokens: 1024,
        debugMode: true,
        apiKeys: {'a': 'b'},
      );
      final s2 = s.copyWith();
      expect(s2.temperature, 0.9);
      expect(s2.maxTokens, 1024);
      expect(s2.debugMode, true);
      expect(s2.apiKeys, {'a': 'b'});
    });
  });

  // ---------------------------------------------------------------------------
  // TopicNode
  // ---------------------------------------------------------------------------
  group('TopicNode', () {
    final created = DateTime.utc(2026, 1, 1, 12);
    final lastMsg = DateTime.utc(2026, 1, 2, 12);

    test('default constructor sets defaults', () {
      final t = TopicNode(
        id: 't1',
        name: 'Work',
        path: 'root.work',
        createdAt: created,
      );
      expect(t.id, 't1');
      expect(t.depth, 0);
      expect(t.unreadCount, 0);
      expect(t.messageCount, 0);
      expect(t.sortOrder, 0);
      expect(t.isExpanded, false);
      expect(t.parentId, isNull);
      expect(t.color, isNull);
      expect(t.children, isEmpty);
    });

    test('fromJson parses nested children recursively', () {
      final json = {
        'id': 'a',
        'name': 'A',
        'path': 'root.a',
        'parent_id': 'root',
        'depth': 1,
        'color': '#000000',
        'icon': 'folder',
        'unread_count': 3,
        'message_count': 10,
        'sort_order': 2,
        'is_expanded': true,
        'created_at': created.toIso8601String(),
        'last_message_at': lastMsg.toIso8601String(),
        'children': [
          {
            'id': 'b',
            'name': 'B',
            'path': 'root.a.b',
            'depth': 2,
            'created_at': created.toIso8601String(),
          }
        ],
      };
      final t = TopicNode.fromJson(json);
      expect(t.id, 'a');
      expect(t.parentId, 'root');
      expect(t.depth, 1);
      expect(t.color, '#000000');
      expect(t.icon, 'folder');
      expect(t.unreadCount, 3);
      expect(t.messageCount, 10);
      expect(t.sortOrder, 2);
      expect(t.isExpanded, true);
      expect(t.lastMessageAt, lastMsg);
      expect(t.children, hasLength(1));
      expect(t.children.first.id, 'b');
      expect(t.children.first.depth, 2);
    });

    test('fromJson handles missing optional fields', () {
      final t = TopicNode.fromJson({
        'id': 'x',
        'name': 'X',
      });
      expect(t.path, '');
      expect(t.depth, 0);
      expect(t.unreadCount, 0);
      expect(t.isExpanded, false);
      expect(t.children, isEmpty);
      expect(t.lastMessageAt, isNull);
    });

    test('fromJson falls back to now on invalid created_at', () {
      final before = DateTime.now();
      final t = TopicNode.fromJson({
        'id': 'x',
        'name': 'X',
        'created_at': 'not-a-date',
      });
      // Fallback is DateTime.now() — should be at or after `before`.
      expect(
        t.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        true,
      );
    });

    test('copyWith replaces provided fields, preserves rest', () {
      final t = TopicNode(
        id: 'a',
        name: 'A',
        path: 'root.a',
        parentId: 'root',
        depth: 1,
        unreadCount: 5,
        createdAt: created,
      );
      final t2 = t.copyWith(name: 'A2', unreadCount: 0, isExpanded: true);
      expect(t2.id, 'a'); // preserved
      expect(t2.name, 'A2');
      expect(t2.unreadCount, 0);
      expect(t2.isExpanded, true);
      expect(t2.parentId, 'root'); // preserved
      expect(t2.depth, 1); // preserved
    });
  });

  // ---------------------------------------------------------------------------
  // QueuedAction
  // ---------------------------------------------------------------------------
  group('QueuedAction', () {
    final now = DateTime.now();
    final past = now.subtract(const Duration(hours: 1));
    final future = now.add(const Duration(hours: 1));

    test('isExpired returns true when expiresAt is in the past', () {
      final q = QueuedAction(
        id: 'q1',
        namespace: 'claw',
        action: 'sync',
        payload: const {},
        status: 'pending',
        createdAt: past,
        expiresAt: past,
      );
      expect(q.isExpired, true);
    });

    test('isExpired returns false when expiresAt is in the future', () {
      final q = QueuedAction(
        id: 'q2',
        namespace: 'claw',
        action: 'sync',
        payload: const {},
        status: 'pending',
        createdAt: now,
        expiresAt: future,
      );
      expect(q.isExpired, false);
    });

    test('fromJson parses payload as Map<String, dynamic>', () {
      final json = {
        'id': 'q1',
        'namespace': 'claw',
        'action': 'sync',
        'payload': {'key': 'value'},
        'idempotency_key': 'idem-1',
        'status': 'pending',
        'created_at': past.toIso8601String(),
        'expires_at': future.toIso8601String(),
      };
      final q = QueuedAction.fromJson(json);
      expect(q.id, 'q1');
      expect(q.payload, {'key': 'value'});
      expect(q.idempotencyKey, 'idem-1');
      expect(q.status, 'pending');
    });

    test('fromJson parses payload as JSON string', () {
      final json = {
        'id': 'q1',
        'payload': jsonEncode({'k': 'v'}),
        'created_at': past.toIso8601String(),
        'expires_at': future.toIso8601String(),
      };
      final q = QueuedAction.fromJson(json);
      expect(q.payload, {'k': 'v'});
    });

    test('fromJson handles invalid payload gracefully', () {
      final json = {
        'id': 'q1',
        'payload': 'not-json!!{',
        'created_at': past.toIso8601String(),
        'expires_at': future.toIso8601String(),
      };
      final q = QueuedAction.fromJson(json);
      expect(q.payload, isEmpty);
    });

    test('fromJson uses defaults for missing fields', () {
      final q = QueuedAction.fromJson({'id': 'q1'});
      expect(q.namespace, '');
      expect(q.action, '');
      expect(q.payload, isEmpty);
      expect(q.status, 'pending');
      // created_at defaults to "now", expires_at defaults to now+24h
      expect(q.expiresAt.isAfter(q.createdAt), true);
    });

    test('toJson contains all fields', () {
      final q = QueuedAction(
        id: 'q1',
        namespace: 'claw',
        action: 'sync',
        payload: const {'a': 1},
        idempotencyKey: 'idem',
        status: 'pending',
        createdAt: past,
        expiresAt: future,
      );
      final m = q.toJson();
      expect(m['id'], 'q1');
      expect(m['namespace'], 'claw');
      expect(m['action'], 'sync');
      expect(m['payload'], {'a': 1});
      expect(m['idempotency_key'], 'idem');
      expect(m['status'], 'pending');
      expect(m['created_at'], past.toIso8601String());
      expect(m['expires_at'], future.toIso8601String());
    });

    test('equality by id', () {
      final q1 = QueuedAction(
        id: 'q',
        namespace: 'a',
        action: 'b',
        payload: const {},
        status: 'p',
        createdAt: past,
        expiresAt: future,
      );
      final q2 = QueuedAction(
        id: 'q',
        namespace: 'different',
        action: 'different',
        payload: const {'diff': 1},
        status: 'done',
        createdAt: now,
        expiresAt: future,
      );
      expect(q1, equals(q2));
      expect(q1.hashCode, q2.hashCode);
    });
  });

  // ---------------------------------------------------------------------------
  // ServerConfig
  // ---------------------------------------------------------------------------
  group('ServerConfig', () {
    test('toJson/fromJson round-trip', () {
      const c = ServerConfig(
        id: 's1',
        url: 'https://example.com',
        name: 'My Server',
        jwtToken: 'jwt',
        refreshToken: 'refresh',
      );
      final json = c.toJson();
      expect(json['id'], 's1');
      expect(json['url'], 'https://example.com');
      expect(json['jwtToken'], 'jwt');

      final c2 = ServerConfig.fromJson(json);
      expect(c2.id, 's1');
      expect(c2.url, 'https://example.com');
      expect(c2.name, 'My Server');
      expect(c2.jwtToken, 'jwt');
      expect(c2.refreshToken, 'refresh');
    });

    test('copyWith replaces provided fields', () {
      const c = ServerConfig(id: 's1', url: 'u', name: 'n');
      final c2 = c.copyWith(url: 'u2', jwtToken: 't');
      expect(c2.id, 's1'); // preserved
      expect(c2.url, 'u2');
      expect(c2.name, 'n');
      expect(c2.jwtToken, 't');
    });

    test('encodeList/decodeList round-trip', () {
      final list = [
        const ServerConfig(id: 'a', url: 'ua', name: 'A'),
        const ServerConfig(
            id: 'b', url: 'ub', name: 'B', jwtToken: 'j', refreshToken: 'r'),
      ];
      final encoded = ServerConfig.encodeList(list);
      expect(encoded, isA<String>());
      final decoded = ServerConfig.decodeList(encoded);
      expect(decoded, hasLength(2));
      expect(decoded.first.id, 'a');
      expect(decoded.last.jwtToken, 'j');
    });

    test('encodeList for empty list returns "[]"', () {
      expect(ServerConfig.encodeList([]), '[]');
      expect(ServerConfig.decodeList('[]'), isEmpty);
    });

    test('equality by id', () {
      const c1 = ServerConfig(id: 'x', url: 'a', name: 'a');
      const c2 = ServerConfig(id: 'x', url: 'b', name: 'b');
      expect(c1, equals(c2));
      expect(c1.hashCode, c2.hashCode);
    });
  });

  // ---------------------------------------------------------------------------
  // MemoryRecord
  // ---------------------------------------------------------------------------
  group('MemoryRecord', () {
    test('fromJson parses all fields', () {
      final created = DateTime.utc(2026, 1, 1);
      final updated = DateTime.utc(2026, 2, 1);
      final json = {
        'id': 'm1',
        'entity_id': 'e1',
        'entity_type': 'fact',
        'content': 'hello',
        'confidence': 0.9,
        'times_reinforced': 5,
        'source': 'chat',
        'status': 'active',
        'metadata': {'a': 1},
        'created_at': created.toIso8601String(),
        'updated_at': updated.toIso8601String(),
      };
      final r = MemoryRecord.fromJson(json);
      expect(r.id, 'm1');
      expect(r.entityId, 'e1');
      expect(r.entityType, 'fact');
      expect(r.content, 'hello');
      expect(r.confidence, 0.9);
      expect(r.timesReinforced, 5);
      expect(r.source, 'chat');
      expect(r.status, 'active');
      expect(r.metadata, {'a': 1});
      expect(r.createdAt, created);
      expect(r.updatedAt, updated);
    });

    test('fromJson falls back for empty and missing fields', () {
      final r = MemoryRecord.fromJson({});
      expect(r.id, '');
      expect(r.entityId, '');
      expect(r.entityType, 'fact');
      expect(r.content, '');
      expect(r.confidence, 1.0);
      expect(r.timesReinforced, 1);
      expect(r.source, '');
      expect(r.status, isNull);
      expect(r.metadata, isNull);
      expect(r.updatedAt, isNull);
    });

    test('default values are applied in constructor', () {
      final r = MemoryRecord(
        id: 'r',
        entityId: 'e',
        entityType: 'fact',
        content: 'c',
        createdAt: DateTime.utc(2026),
      );
      expect(r.confidence, 1.0);
      expect(r.timesReinforced, 1);
      expect(r.source, '');
      expect(r.updatedAt, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // ClawAction
  // ---------------------------------------------------------------------------
  group('ClawAction', () {
    final now = DateTime.now();
    final past = now.subtract(const Duration(hours: 1));
    final future = now.add(const Duration(hours: 1));

    group('ActionType', () {
      test('toJson returns name', () {
        expect(ActionType.fileOp.toJson(), 'fileOp');
        expect(ActionType.shell.toJson(), 'shell');
      });
      test('fromJson matches known values', () {
        expect(ActionType.fromJson('browser'), ActionType.browser);
        expect(ActionType.fromJson('oauth'), ActionType.oauth);
      });
      test('fromJson defaults to notification for unknown', () {
        expect(ActionType.fromJson('unknown'), ActionType.notification);
        expect(ActionType.fromJson(''), ActionType.notification);
      });
    });

    group('ActionStatus', () {
      test('toJson returns name', () {
        expect(ActionStatus.pending.toJson(), 'pending');
        expect(ActionStatus.done.toJson(), 'done');
      });
      test('fromJson matches known values', () {
        expect(ActionStatus.fromJson('failed'), ActionStatus.failed);
        expect(ActionStatus.fromJson('approved'), ActionStatus.approved);
      });
      test('fromJson defaults to pending for unknown', () {
        expect(ActionStatus.fromJson('garbage'), ActionStatus.pending);
      });
    });

    test('isPending true when status=pending and not expired', () {
      final a = ClawAction(
        id: 'a1',
        sessionId: 's',
        type: ActionType.fileOp,
        params: const {},
        status: ActionStatus.pending,
        createdAt: past,
        expiresAt: future,
      );
      expect(a.isPending, true);
      expect(a.isExpired, false);
      expect(a.isTerminal, false);
    });

    test('isPending false when expired', () {
      final a = ClawAction(
        id: 'a1',
        sessionId: 's',
        type: ActionType.fileOp,
        params: const {},
        status: ActionStatus.pending,
        createdAt: past,
        expiresAt: past,
      );
      expect(a.isPending, false);
      expect(a.isExpired, true);
    });

    test('isTerminal true for done/failed/expired', () {
      for (final s in [
        ActionStatus.done,
        ActionStatus.failed,
        ActionStatus.expired,
      ]) {
        final a = ClawAction(
          id: 'a',
          sessionId: 's',
          type: ActionType.shell,
          params: const {},
          status: s,
          createdAt: past,
          expiresAt: future,
        );
        expect(a.isTerminal, true, reason: 'status=$s should be terminal');
      }
    });

    test('copyWith replaces status/result/executedAt only', () {
      final a = ClawAction(
        id: 'a1',
        sessionId: 's',
        type: ActionType.shell,
        params: const {'cmd': 'ls'},
        status: ActionStatus.pending,
        createdAt: past,
        expiresAt: future,
      );
      final exec = DateTime.now();
      final a2 = a.copyWith(
        status: ActionStatus.done,
        result: const {'ok': true},
        executedAt: exec,
      );
      expect(a2.id, 'a1');
      expect(a2.sessionId, 's');
      expect(a2.status, ActionStatus.done);
      expect(a2.result, {'ok': true});
      expect(a2.executedAt, exec);
      expect(a2.params, {'cmd': 'ls'});
    });

    test('toMap/fromMap SQLite round-trip', () {
      final a = ClawAction(
        id: 'a1',
        sessionId: 's',
        type: ActionType.fileOp,
        params: const {'path': '/tmp'},
        status: ActionStatus.pending,
        result: const {'bytes': 100},
        createdAt: past,
        executedAt: now,
        expiresAt: future,
      );
      final map = a.toMap();
      expect(map['id'], 'a1');
      expect(map['type'], 'fileOp');
      expect(map['params'], isA<String>()); // encoded JSON
      expect(map['result'], isA<String>());
      final a2 = ClawAction.fromMap(map);
      expect(a2.id, 'a1');
      expect(a2.type, ActionType.fileOp);
      expect(a2.params, {'path': '/tmp'});
      expect(a2.result, {'bytes': 100});
      expect(a2.status, ActionStatus.pending);
    });

    test('toMap handles null result', () {
      final a = ClawAction(
        id: 'a1',
        sessionId: 's',
        type: ActionType.fileOp,
        params: const {},
        status: ActionStatus.pending,
        createdAt: past,
        expiresAt: future,
      );
      final map = a.toMap();
      expect(map['result'], isNull);
      expect(map['executed_at'], isNull);
    });

    test('fromJson parses WS payload', () {
      final json = {
        'id': 'a1',
        'sessionId': 's',
        'type': 'oauth',
        'status': 'approved',
        'params': {'code': 'x'},
        'createdAt': past.toIso8601String(),
        'expiresAt': future.toIso8601String(),
      };
      final a = ClawAction.fromJson(json);
      expect(a.id, 'a1');
      expect(a.sessionId, 's');
      expect(a.type, ActionType.oauth);
      expect(a.status, ActionStatus.approved);
      expect(a.params, {'code': 'x'});
    });

    test('fromJson falls back on missing timestamps', () {
      final before = DateTime.now();
      final a = ClawAction.fromJson({'id': 'a1'});
      expect(a.sessionId, '');
      expect(a.type, ActionType.notification);
      expect(a.status, ActionStatus.pending);
      expect(a.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
          true);
      // expiresAt defaults to now + 24h
      expect(a.expiresAt.isAfter(a.createdAt), true);
    });

    test('equality by id', () {
      final a1 = ClawAction(
        id: 'x',
        sessionId: 's',
        type: ActionType.fileOp,
        params: const {},
        status: ActionStatus.pending,
        createdAt: past,
        expiresAt: future,
      );
      final a2 = ClawAction(
        id: 'x',
        sessionId: 'different',
        type: ActionType.browser,
        params: const {'a': 1},
        status: ActionStatus.done,
        createdAt: now,
        expiresAt: future,
      );
      expect(a1, equals(a2));
      expect(a1.hashCode, a2.hashCode);
    });
  });
}
