// Miscellaneous edge-case coverage tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/models/server_config.dart';
import 'package:nself_claw/models/topic_node.dart';

void main() {
  group('ServerConfig decode edge cases', () {
    test('decodeList on malformed JSON throws FormatException', () {
      expect(
        () => ServerConfig.decodeList('not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodeList of []', () {
      expect(ServerConfig.decodeList('[]'), isEmpty);
    });
  });

  group('TopicNode edge cases', () {
    test('children with deep nesting parses recursively', () {
      final json = {
        'id': 'a',
        'name': 'A',
        'children': [
          {
            'id': 'b',
            'name': 'B',
            'children': [
              {'id': 'c', 'name': 'C'},
            ]
          }
        ],
      };
      final t = TopicNode.fromJson(json);
      expect(t.children, hasLength(1));
      expect(t.children.first.children, hasLength(1));
      expect(t.children.first.children.first.id, 'c');
    });

    test('copyWith on a node with children preserves the children', () {
      final created = DateTime.utc(2026);
      final leaf = TopicNode(id: 'l', name: 'L', path: 'x', createdAt: created);
      final parent = TopicNode(
        id: 'p',
        name: 'P',
        path: 'x',
        createdAt: created,
        children: [leaf],
      );
      final p2 = parent.copyWith(name: 'P2');
      expect(p2.children, hasLength(1));
      expect(p2.children.first.id, 'l');
    });

    test('copyWith can replace children list', () {
      final created = DateTime.utc(2026);
      final t = TopicNode(
        id: 'p',
        name: 'P',
        path: 'x',
        createdAt: created,
        children: const [],
      );
      final replaced = TopicNode(
          id: 'c', name: 'C', path: 'p.c', createdAt: created);
      final t2 = t.copyWith(children: [replaced]);
      expect(t2.children, hasLength(1));
      expect(t2.children.first.id, 'c');
    });
  });
}
