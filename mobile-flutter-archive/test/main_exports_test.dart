// Tests for standalone classes / providers exported by main.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/main.dart';

void main() {
  group('DeepLinkPayload', () {
    test('constructor with route and id', () {
      const p = DeepLinkPayload(route: 'topics', id: 't1');
      expect(p.route, 'topics');
      expect(p.id, 't1');
    });

    test('constructor with only route', () {
      const p = DeepLinkPayload(route: 'digest');
      expect(p.route, 'digest');
      expect(p.id, isNull);
    });
  });
}
