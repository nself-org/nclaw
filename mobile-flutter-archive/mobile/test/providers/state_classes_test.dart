// Unit tests for Riverpod state classes and pure data portions of providers.
// These classes have zero platform deps; testing them is cheap coverage and
// catches regressions in copyWith semantics.

import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/models/claw_action.dart';
import 'package:nself_claw/models/topic_node.dart';
import 'package:nself_claw/providers/action_provider.dart';
import 'package:nself_claw/providers/topic_provider.dart';
import 'package:nself_claw/providers/voice_settings_provider.dart';
import 'package:nself_claw/services/deep_link_service.dart' as dls;

void main() {
  // ---------------------------------------------------------------------------
  // ActionQueueState
  // ---------------------------------------------------------------------------
  group('ActionQueueState', () {
    test('default constructor sets empty lists and loading=true', () {
      const s = ActionQueueState();
      expect(s.pending, isEmpty);
      expect(s.active, isEmpty);
      expect(s.history, isEmpty);
      expect(s.loading, true);
      expect(s.pendingCount, 0);
    });

    test('pendingCount reflects pending length', () {
      final a = ClawAction(
        id: 'a',
        sessionId: 's',
        type: ActionType.shell,
        params: const {},
        status: ActionStatus.pending,
        createdAt: DateTime(2026),
        expiresAt: DateTime(2030),
      );
      final s = ActionQueueState(pending: [a, a, a]);
      expect(s.pendingCount, 3);
    });

    test('copyWith replaces provided lists, preserves others', () {
      final a = ClawAction(
        id: 'a',
        sessionId: 's',
        type: ActionType.shell,
        params: const {},
        status: ActionStatus.pending,
        createdAt: DateTime(2026),
        expiresAt: DateTime(2030),
      );
      const base = ActionQueueState();
      final updated = base.copyWith(
        pending: [a],
        loading: false,
      );
      expect(updated.pending, hasLength(1));
      expect(updated.active, isEmpty); // preserved
      expect(updated.history, isEmpty); // preserved
      expect(updated.loading, false);
    });

    test('ActionTab has three values', () {
      expect(ActionTab.values, hasLength(3));
      expect(ActionTab.pending.name, 'pending');
      expect(ActionTab.active.name, 'active');
      expect(ActionTab.history.name, 'history');
    });
  });

  // ---------------------------------------------------------------------------
  // TopicTreeState
  // ---------------------------------------------------------------------------
  group('TopicTreeState', () {
    test('isEmpty true when no loading, no topics, no error', () {
      const s = TopicTreeState();
      expect(s.isEmpty, true);
    });

    test('isEmpty false when loading', () {
      const s = TopicTreeState(loading: true);
      expect(s.isEmpty, false);
    });

    test('isEmpty false when topics non-empty', () {
      final t = TopicNode(
        id: 't',
        name: 'n',
        path: 'p',
        createdAt: DateTime(2026),
      );
      final s = TopicTreeState(topics: [t]);
      expect(s.isEmpty, false);
    });

    test('isEmpty false when error set', () {
      const s = TopicTreeState(error: 'boom');
      expect(s.isEmpty, false);
    });

    test('copyWith replaces specified fields', () {
      const base = TopicTreeState();
      final updated = base.copyWith(
        loading: true,
        selectedTopicId: 'abc',
        filterQuery: 'q',
      );
      expect(updated.loading, true);
      expect(updated.selectedTopicId, 'abc');
      expect(updated.filterQuery, 'q');
      expect(updated.topics, isEmpty);
    });

    test('copyWith clears error when not passed (by design)', () {
      const base = TopicTreeState(error: 'previous');
      final updated = base.copyWith(loading: true);
      // Implementation: `error: error` — since not passed, error is null.
      expect(updated.error, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // VoiceSettings
  // ---------------------------------------------------------------------------
  group('VoiceSettings', () {
    test('defaults are reasonable', () {
      const v = VoiceSettings();
      expect(v.sttProvider, SttProvider.os);
      expect(v.sttLocale, 'en-US');
      expect(v.inputMode, VoiceInputMode.tapToggle);
      expect(v.autoSendDelay, 1.5);
      expect(v.autoSend, false);
      expect(v.ttsProvider, TtsProvider.os);
      expect(v.ttsVoiceName, '');
      expect(v.ttsSpeed, 1.0);
      expect(v.ttsPitch, 1.0);
      expect(v.autoPlay, false);
      expect(v.streamingTts, true);
    });

    test('toJson emits all snake_case keys', () {
      const v = VoiceSettings(
        sttProvider: SttProvider.whisperApi,
        sttLocale: 'de-DE',
        inputMode: VoiceInputMode.continuous,
        autoSendDelay: 2.0,
        autoSend: true,
        ttsProvider: TtsProvider.server,
        ttsVoiceName: 'Alice',
        ttsSpeed: 1.25,
        ttsPitch: 0.9,
        autoPlay: true,
        streamingTts: false,
      );
      final j = v.toJson();
      expect(j['stt_provider'], 'whisperApi');
      expect(j['stt_locale'], 'de-DE');
      expect(j['input_mode'], 'continuous');
      expect(j['auto_send_delay'], 2.0);
      expect(j['auto_send'], true);
      expect(j['tts_provider'], 'server');
      expect(j['tts_voice_name'], 'Alice');
      expect(j['tts_speed'], 1.25);
      expect(j['tts_pitch'], 0.9);
      expect(j['auto_play'], true);
      expect(j['streaming_tts'], false);
    });

    test('fromJson parses known values', () {
      final j = {
        'stt_provider': 'whisperLocal',
        'stt_locale': 'fr-FR',
        'input_mode': 'pushToTalk',
        'auto_send_delay': 0.75,
        'auto_send': true,
        'tts_provider': 'server',
        'tts_voice_name': 'Bob',
        'tts_speed': 1.5,
        'tts_pitch': 1.2,
        'auto_play': true,
        'streaming_tts': false,
      };
      final v = VoiceSettings.fromJson(j);
      expect(v.sttProvider, SttProvider.whisperLocal);
      expect(v.sttLocale, 'fr-FR');
      expect(v.inputMode, VoiceInputMode.pushToTalk);
      expect(v.autoSendDelay, 0.75);
      expect(v.autoSend, true);
      expect(v.ttsProvider, TtsProvider.server);
      expect(v.ttsVoiceName, 'Bob');
      expect(v.ttsSpeed, 1.5);
      expect(v.ttsPitch, 1.2);
      expect(v.autoPlay, true);
      expect(v.streamingTts, false);
    });

    test('fromJson falls back to defaults for unknown enum values', () {
      final v = VoiceSettings.fromJson({
        'stt_provider': 'bogus',
        'input_mode': 'unknown-mode',
        'tts_provider': 'nope',
      });
      expect(v.sttProvider, SttProvider.os);
      expect(v.inputMode, VoiceInputMode.tapToggle);
      expect(v.ttsProvider, TtsProvider.os);
    });

    test('fromJson fills missing fields with defaults', () {
      final v = VoiceSettings.fromJson({});
      expect(v.sttLocale, 'en-US');
      expect(v.autoSendDelay, 1.5);
      expect(v.ttsSpeed, 1.0);
      expect(v.ttsPitch, 1.0);
      expect(v.autoPlay, false);
      expect(v.streamingTts, true);
    });

    test('copyWith replaces provided fields, preserves rest', () {
      const v = VoiceSettings(sttLocale: 'en-US', ttsSpeed: 1.0);
      final v2 = v.copyWith(sttLocale: 'es-ES', ttsSpeed: 1.25);
      expect(v2.sttLocale, 'es-ES');
      expect(v2.ttsSpeed, 1.25);
      expect(v2.inputMode, VoiceInputMode.tapToggle); // preserved default
    });

    test('copyWith with no args preserves everything', () {
      const v = VoiceSettings(
        sttProvider: SttProvider.whisperApi,
        ttsSpeed: 2.0,
        autoPlay: true,
      );
      final v2 = v.copyWith();
      expect(v2.sttProvider, SttProvider.whisperApi);
      expect(v2.ttsSpeed, 2.0);
      expect(v2.autoPlay, true);
    });
  });

  // ---------------------------------------------------------------------------
  // PairParams (deep_link_service)
  // ---------------------------------------------------------------------------
  group('PairParams', () {
    test('stores serverUrl and code', () {
      const p = dls.PairParams(
          serverUrl: 'https://nclaw.example.com', code: 'ABCDEF');
      expect(p.serverUrl, 'https://nclaw.example.com');
      expect(p.code, 'ABCDEF');
    });
  });
}
