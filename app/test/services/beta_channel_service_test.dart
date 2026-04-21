// Unit tests for BetaChannelService. Uses the FlutterSecureStorage mock
// method channel to simulate the in-memory store.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/services/beta_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        switch (call.method) {
          case 'read':
            final key = (call.arguments as Map)['key'] as String;
            return store[key];
          case 'write':
            final args = call.arguments as Map;
            final key = args['key'] as String;
            final value = args['value'] as String?;
            if (value == null) {
              store.remove(key);
            } else {
              store[key] = value;
            }
            return null;
          case 'delete':
            final key = (call.arguments as Map)['key'] as String;
            store.remove(key);
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

  group('BetaChannelService', () {
    test('isBetaOptedIn returns false on first launch', () async {
      expect(await BetaChannelService.isBetaOptedIn(), false);
    });

    test('setBetaOptIn(true) then isBetaOptedIn returns true', () async {
      await BetaChannelService.setBetaOptIn(true);
      expect(await BetaChannelService.isBetaOptedIn(), true);
    });

    test('setBetaOptIn(false) then isBetaOptedIn returns false', () async {
      await BetaChannelService.setBetaOptIn(true);
      await BetaChannelService.setBetaOptIn(false);
      expect(await BetaChannelService.isBetaOptedIn(), false);
    });

    test('getFeedUrl returns stable URL when not opted in', () async {
      final mac = await BetaChannelService.getFeedUrl('macos_appcast');
      expect(mac, 'https://downloads.nself.org/claw/macos/appcast.xml');
      final win = await BetaChannelService.getFeedUrl('windows_releases');
      expect(win, 'https://downloads.nself.org/claw/windows/RELEASES');
      final lin = await BetaChannelService.getFeedUrl('linux_latest');
      expect(lin, 'https://downloads.nself.org/claw/linux/latest.json');
    });

    test('getFeedUrl returns beta URL when opted in', () async {
      await BetaChannelService.setBetaOptIn(true);
      final mac = await BetaChannelService.getFeedUrl('macos_appcast');
      expect(mac,
          'https://downloads.nself.org/claw/beta/macos/appcast-beta.xml');
      final win = await BetaChannelService.getFeedUrl('windows_releases');
      expect(win,
          'https://downloads.nself.org/claw/beta/windows/RELEASES-beta');
      final lin = await BetaChannelService.getFeedUrl('linux_latest');
      expect(lin, 'https://downloads.nself.org/claw/beta/linux/latest.json');
    });

    test('getFeedUrl returns null for unknown platform', () async {
      final v = await BetaChannelService.getFeedUrl('vision_pro');
      expect(v, isNull);
    });

    test('getAllFeedUrls returns stable map when not opted in', () async {
      final all = await BetaChannelService.getAllFeedUrls();
      expect(all, hasLength(3));
      expect(all.keys, containsAll(const [
        'macos_appcast',
        'windows_releases',
        'linux_latest',
      ]));
      expect(all['macos_appcast'],
          'https://downloads.nself.org/claw/macos/appcast.xml');
    });

    test('getAllFeedUrls returns beta map when opted in', () async {
      await BetaChannelService.setBetaOptIn(true);
      final all = await BetaChannelService.getAllFeedUrls();
      expect(all, hasLength(3));
      expect(all['macos_appcast'],
          'https://downloads.nself.org/claw/beta/macos/appcast-beta.xml');
    });
  });
}
