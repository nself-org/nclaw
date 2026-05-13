// T-1115: Voice settings — persisted via FlutterSecureStorage.
//
// Holds STT and TTS preferences. Syncs to POST /claw/voice/settings on
// change when a server URL is available. VoiceSettingsScreen reads and
// writes through this provider.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

enum SttProvider { os, whisperLocal, whisperApi }
enum TtsProvider { os, server }
enum VoiceInputMode { pushToTalk, tapToggle, continuous }

class VoiceSettings {
  // STT
  final SttProvider sttProvider;
  final String sttLocale;
  final VoiceInputMode inputMode;
  final double autoSendDelay; // seconds 0.5–3.0
  final bool autoSend;

  // TTS
  final TtsProvider ttsProvider;
  final String ttsVoiceName;
  final double ttsSpeed;  // 0.5–2.0 (mapped 0.25–1.0 for flutter_tts)
  final double ttsPitch;  // 0.5–2.0
  final bool autoPlay;
  final bool streamingTts;

  const VoiceSettings({
    this.sttProvider = SttProvider.os,
    this.sttLocale = 'en-US',
    this.inputMode = VoiceInputMode.tapToggle,
    this.autoSendDelay = 1.5,
    this.autoSend = false,
    this.ttsProvider = TtsProvider.os,
    this.ttsVoiceName = '',
    this.ttsSpeed = 1.0,
    this.ttsPitch = 1.0,
    this.autoPlay = false,
    this.streamingTts = true,
  });

  VoiceSettings copyWith({
    SttProvider? sttProvider,
    String? sttLocale,
    VoiceInputMode? inputMode,
    double? autoSendDelay,
    bool? autoSend,
    TtsProvider? ttsProvider,
    String? ttsVoiceName,
    double? ttsSpeed,
    double? ttsPitch,
    bool? autoPlay,
    bool? streamingTts,
  }) {
    return VoiceSettings(
      sttProvider: sttProvider ?? this.sttProvider,
      sttLocale: sttLocale ?? this.sttLocale,
      inputMode: inputMode ?? this.inputMode,
      autoSendDelay: autoSendDelay ?? this.autoSendDelay,
      autoSend: autoSend ?? this.autoSend,
      ttsProvider: ttsProvider ?? this.ttsProvider,
      ttsVoiceName: ttsVoiceName ?? this.ttsVoiceName,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      autoPlay: autoPlay ?? this.autoPlay,
      streamingTts: streamingTts ?? this.streamingTts,
    );
  }

  Map<String, dynamic> toJson() => {
        'stt_provider': sttProvider.name,
        'stt_locale': sttLocale,
        'input_mode': inputMode.name,
        'auto_send_delay': autoSendDelay,
        'auto_send': autoSend,
        'tts_provider': ttsProvider.name,
        'tts_voice_name': ttsVoiceName,
        'tts_speed': ttsSpeed,
        'tts_pitch': ttsPitch,
        'auto_play': autoPlay,
        'streaming_tts': streamingTts,
      };

  factory VoiceSettings.fromJson(Map<String, dynamic> j) => VoiceSettings(
        sttProvider: SttProvider.values.firstWhere(
          (e) => e.name == j['stt_provider'],
          orElse: () => SttProvider.os,
        ),
        sttLocale: j['stt_locale'] as String? ?? 'en-US',
        inputMode: VoiceInputMode.values.firstWhere(
          (e) => e.name == j['input_mode'],
          orElse: () => VoiceInputMode.tapToggle,
        ),
        autoSendDelay: (j['auto_send_delay'] as num?)?.toDouble() ?? 1.5,
        autoSend: j['auto_send'] as bool? ?? false,
        ttsProvider: TtsProvider.values.firstWhere(
          (e) => e.name == j['tts_provider'],
          orElse: () => TtsProvider.os,
        ),
        ttsVoiceName: j['tts_voice_name'] as String? ?? '',
        ttsSpeed: (j['tts_speed'] as num?)?.toDouble() ?? 1.0,
        ttsPitch: (j['tts_pitch'] as num?)?.toDouble() ?? 1.0,
        autoPlay: j['auto_play'] as bool? ?? false,
        streamingTts: j['streaming_tts'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class VoiceSettingsNotifier extends StateNotifier<VoiceSettings> {
  final FlutterSecureStorage _storage;
  static const _storageKey = 'np_claw_voice_settings';

  VoiceSettingsNotifier({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super(const VoiceSettings());

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      try {
        state = VoiceSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        // Corrupted — use defaults.
      }
    }
  }

  Future<void> update(VoiceSettings settings, {String? serverUrl}) async {
    state = settings;
    await _storage.write(key: _storageKey, value: jsonEncode(settings.toJson()));
    if (serverUrl != null && serverUrl.isNotEmpty) {
      _syncToServer(settings, serverUrl);
    }
  }

  void _syncToServer(VoiceSettings settings, String serverUrl) {
    http
        .post(
          Uri.parse('$serverUrl/claw/voice/settings'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(settings.toJson()),
        )
        .ignore(); // fire-and-forget; failures are non-critical
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final voiceSettingsProvider =
    StateNotifierProvider<VoiceSettingsNotifier, VoiceSettings>(
  (ref) {
    final notifier = VoiceSettingsNotifier();
    notifier.load();
    return notifier;
  },
);
