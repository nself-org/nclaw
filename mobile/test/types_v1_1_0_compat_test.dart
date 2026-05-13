import 'package:flutter_test/flutter_test.dart';
import 'package:nclaw/src/rust/api/types.dart';

void main() {
  group('Message v1.1.0 compatibility', () {
    test('Message.fromJson and toJson round-trip without data loss', () {
      final fixture = {
        'id': 'msg-001',
        'conversation_id': 'conv-001',
        'role': 'user',
        'content': 'Hello, nClaw!',
        'created_at': '2026-05-13T10:00:00Z',
      };

      final message = Message.fromJson(fixture);
      final roundTripped = message.toJson();

      expect(roundTripped['id'], equals(fixture['id']));
      expect(roundTripped['conversation_id'], equals(fixture['conversation_id']));
      expect(roundTripped['role'], equals(fixture['role']));
      expect(roundTripped['content'], equals(fixture['content']));
      expect(roundTripped['created_at'], equals(fixture['created_at']));
    });
  });

  group('Topic v1.1.0 compatibility', () {
    test('Topic.fromJson and toJson round-trip without data loss', () {
      final fixture = {
        'id': 'topic-001',
        'path': '/work/projects',
        'name': 'Projects',
        'archived': false,
      };

      final topic = Topic.fromJson(fixture);
      final roundTripped = topic.toJson();

      expect(roundTripped['id'], equals(fixture['id']));
      expect(roundTripped['path'], equals(fixture['path']));
      expect(roundTripped['name'], equals(fixture['name']));
      expect(roundTripped['archived'], equals(fixture['archived']));
    });

    test('Topic handles archived=null as false', () {
      final fixture = {
        'id': 'topic-002',
        'path': '/archive',
        'name': 'Archive',
      };

      final topic = Topic.fromJson(fixture);
      expect(topic.archived, equals(false));
    });
  });

  group('Memory v1.1.0 compatibility', () {
    test('Memory.fromJson and toJson round-trip without data loss', () {
      final fixture = {
        'id': 'mem-001',
        'content': 'User prefers async tasks',
        'confidence': 0.95,
      };

      final memory = Memory.fromJson(fixture);
      final roundTripped = memory.toJson();

      expect(roundTripped['id'], equals(fixture['id']));
      expect(roundTripped['content'], equals(fixture['content']));
      expect(roundTripped['confidence'], equals(fixture['confidence']));
    });
  });
}
