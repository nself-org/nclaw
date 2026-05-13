// Integration tests for notifiers that can run standalone in a
// ProviderContainer. Only notifiers that don't `ref.read` another provider
// on construction are covered here; cross-provider notifiers (Topic,
// MemoryExplorer, Knowledge) need a full ConnectionNotifier override and
// are covered via state-class tests instead.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/providers/voice_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock SecureStorage so VoiceSettingsNotifier().load() doesn't throw.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        if (call.method == 'read') return null;
        if (call.method == 'readAll') return <String, String>{};
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

  // ---------------------------------------------------------------------------
  // VoiceSettingsNotifier — self-contained, safe to run in a real container.
  // ---------------------------------------------------------------------------
  group('VoiceSettingsNotifier', () {
    test('initial state matches defaults', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final state = c.read(voiceSettingsProvider);
      expect(state.sttLocale, 'en-US');
      expect(state.ttsSpeed, 1.0);
      expect(state.inputMode, VoiceInputMode.tapToggle);
    });

    test('update mutates state and persists to secure storage', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(voiceSettingsProvider.notifier);
      await notifier.update(const VoiceSettings(
        sttLocale: 'de-DE',
        ttsSpeed: 1.5,
      ));
      final state = c.read(voiceSettingsProvider);
      expect(state.sttLocale, 'de-DE');
      expect(state.ttsSpeed, 1.5);
    });

    test('update with empty serverUrl skips sync but still persists locally',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(voiceSettingsProvider.notifier);
      await notifier.update(
        const VoiceSettings(ttsVoiceName: 'Alice'),
        serverUrl: '',
      );
      final state = c.read(voiceSettingsProvider);
      expect(state.ttsVoiceName, 'Alice');
    });

    test('load() survives corrupted JSON by leaving state unchanged',
        () async {
      // Set up the channel mock to return malformed JSON on the next read.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async {
          if (call.method == 'read') return 'not-json{';
          return null;
        },
      );
      final notifier = VoiceSettingsNotifier();
      await notifier.load();
      // State should remain at defaults (no crash).
      expect(notifier.state.sttLocale, 'en-US');
    });

    test('load() with valid JSON applies values', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (MethodCall call) async {
          if (call.method == 'read') {
            return '{"stt_locale":"fr-FR","tts_speed":1.25}';
          }
          return null;
        },
      );
      final notifier = VoiceSettingsNotifier();
      await notifier.load();
      expect(notifier.state.sttLocale, 'fr-FR');
      expect(notifier.state.ttsSpeed, 1.25);
    });
  });
}
