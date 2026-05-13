// Unit tests for settingsProvider. Uses ProviderContainer to construct the
// SettingsNotifier and the Flutter SecureStorage mock so _load() returns
// null on first launch.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/models/app_settings.dart';
import 'package:nself_claw/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final args = call.arguments as Map?;
        final key = args?['key'] as String?;
        switch (call.method) {
          case 'read':
            return key != null ? store[key] : null;
          case 'write':
            final value = args!['value'] as String?;
            if (key != null) {
              if (value == null) {
                store.remove(key);
              } else {
                store[key] = value;
              }
            }
            return null;
          case 'readAll':
            return Map<String, String>.from(store);
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

  group('settingsProvider', () {
    test('initial state matches defaults when storage is empty', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Allow the constructor's _load to settle.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final s = c.read(settingsProvider);
      expect(s.displayName, '');
      expect(s.theme, 'system');
      expect(s.temperature, 0.7);
    });

    test('update mutates state and persists', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final notifier = c.read(settingsProvider.notifier);
      await notifier.update((s) => s.copyWith(
            displayName: 'Ada',
            theme: 'dark',
          ));
      final s = c.read(settingsProvider);
      expect(s.displayName, 'Ada');
      expect(s.theme, 'dark');
      // Storage should contain JSON with the new values.
      expect(store['nclaw_app_settings'], isNotNull);
      expect(store['nclaw_app_settings'], contains('Ada'));
    });

    test('subsequent update preserves previously saved fields', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final notifier = c.read(settingsProvider.notifier);
      await notifier.update((s) => s.copyWith(displayName: 'A'));
      await notifier.update((s) => s.copyWith(theme: 'light'));
      final s = c.read(settingsProvider);
      expect(s.displayName, 'A');
      expect(s.theme, 'light');
    });

    test('SettingsNotifier loads existing JSON from storage on init',
        () async {
      const json =
          '{"display_name":"Preloaded","theme":"dark","temperature":0.3}';
      store['nclaw_app_settings'] = json;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Trigger construction, then wait long enough for async _load().
      c.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final s = c.read(settingsProvider);
      expect(s.displayName, 'Preloaded');
      expect(s.theme, 'dark');
      expect(s.temperature, 0.3);
    });

    test('SettingsNotifier survives corrupted JSON by keeping defaults',
        () async {
      store['nclaw_app_settings'] = 'not-json{';
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final s = c.read(settingsProvider);
      expect(s.displayName, ''); // default
    });

    test('update roundtrips an AppSettings through JSON', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final notifier = c.read(settingsProvider.notifier);
      await notifier.update((_) => const AppSettings(
            displayName: 'Round',
            language: 'fr',
            temperature: 0.5,
            apiKeys: {'openai': 'sk-xyz'},
          ));
      final s = c.read(settingsProvider);
      expect(s.language, 'fr');
      expect(s.apiKeys['openai'], 'sk-xyz');
    });
  });
}
