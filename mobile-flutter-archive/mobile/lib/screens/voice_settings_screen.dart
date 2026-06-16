// T-1115: Voice settings screen — STT + TTS configuration.
//
// STT section:  provider, language, input mode, auto-send delay.
// TTS section:  provider, voice picker, speed, pitch, auto-play, streaming TTS.
// Test buttons: "Test STT" (3 s record), "Test TTS" (sample sentence).
// Settings persist via FlutterSecureStorage and sync to POST /claw/voice/settings.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../providers/voice_settings_provider.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';

class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  final SttService _stt = SttService();
  final TtsService _tts = TtsService();

  List<SttLocale> _sttLocales = const [SttLocale(id: 'en-US', name: 'English (US)')];
  List<VoiceInfo> _ttsVoices = const [];

  bool _testingStt = false;
  bool _testingTts = false;
  String _sttTestResult = '';

  Timer? _sttTestTimer;

  @override
  void initState() {
    super.initState();
    _loadLocalesAndVoices();
  }

  @override
  void dispose() {
    _sttTestTimer?.cancel();
    _stt.stopListening();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadLocalesAndVoices() async {
    await _stt.initialize();
    await _tts.initialize();

    final locales = await _stt.getLocales();
    final voices = await _tts.getAvailableVoices();

    if (mounted) {
      setState(() {
        _sttLocales = locales.isEmpty
            ? const [SttLocale(id: 'en-US', name: 'English (US)')]
            : locales;
        _ttsVoices = voices;
      });
    }
  }

  void _save(VoiceSettings updated) {
    final serverUrl =
        ref.read(connectionProvider).activeServer?.url ?? '';
    ref
        .read(voiceSettingsProvider.notifier)
        .update(updated, serverUrl: serverUrl);
  }

  // -------------------------------------------------------------------------
  // Test STT
  // -------------------------------------------------------------------------

  Future<void> _testStt() async {
    if (_testingStt) return;
    final settings = ref.read(voiceSettingsProvider);
    setState(() {
      _testingStt = true;
      _sttTestResult = 'Listening for 3 s…';
    });
    await _stt.startListening(
      locale: settings.sttLocale,
      onResult: (text, _) {
        if (mounted) setState(() => _sttTestResult = text.isEmpty ? '…' : text);
      },
    );
    _sttTestTimer = Timer(const Duration(seconds: 3), () async {
      await _stt.stopListening();
      if (mounted) setState(() => _testingStt = false);
    });
  }

  // -------------------------------------------------------------------------
  // Test TTS
  // -------------------------------------------------------------------------

  Future<void> _testTts() async {
    if (_testingTts) return;
    final settings = ref.read(voiceSettingsProvider);
    setState(() => _testingTts = true);
    await _tts.setSpeechRate(settings.ttsSpeed / 2.0); // map 0.5–2.0 → 0.25–1.0
    if (settings.ttsVoiceName.isNotEmpty) {
      await _tts.setVoice(settings.ttsVoiceName);
    }
    _tts.onComplete(() {
      if (mounted) setState(() => _testingTts = false);
    });
    await _tts.speak('Hello! This is how \u0273Claw sounds with the current settings.');
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(voiceSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Voice Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ----------------------------------------------------------------
          // STT section
          // ----------------------------------------------------------------
          _SectionHeader(title: 'Speech to Text', theme: theme),
          const SizedBox(height: 8),

          // STT provider
          _DropdownTile<SttProvider>(
            label: 'Provider',
            value: settings.sttProvider,
            items: const {
              SttProvider.os: 'Device (OS)',
              SttProvider.whisperLocal: 'Whisper Local',
              SttProvider.whisperApi: 'Whisper API',
            },
            onChanged: (v) => _save(settings.copyWith(sttProvider: v)),
          ),

          // Language
          _DropdownTile<String>(
            label: 'Language',
            value: _sttLocales.any((l) => l.id == settings.sttLocale)
                ? settings.sttLocale
                : _sttLocales.first.id,
            items: {for (final l in _sttLocales) l.id: l.name},
            onChanged: (v) => _save(settings.copyWith(sttLocale: v)),
          ),

          // Input mode
          _DropdownTile<VoiceInputMode>(
            label: 'Input mode',
            value: settings.inputMode,
            items: const {
              VoiceInputMode.tapToggle: 'Tap to toggle',
              VoiceInputMode.pushToTalk: 'Push to talk',
              VoiceInputMode.continuous: 'Continuous',
            },
            onChanged: (v) => _save(settings.copyWith(inputMode: v)),
          ),

          // Auto-send toggle
          SwitchListTile(
            title: const Text('Auto-send after silence'),
            value: settings.autoSend,
            onChanged: (v) => _save(settings.copyWith(autoSend: v)),
          ),

          // Auto-send delay
          if (settings.autoSend) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Silence delay'),
                  Expanded(
                    child: Slider(
                      value: settings.autoSendDelay,
                      min: 0.5,
                      max: 3.0,
                      divisions: 10,
                      label: '${settings.autoSendDelay.toStringAsFixed(1)} s',
                      onChanged: (v) =>
                          _save(settings.copyWith(autoSendDelay: v)),
                    ),
                  ),
                  Text(
                    '${settings.autoSendDelay.toStringAsFixed(1)} s',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],

          // Test STT
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.tonal(
                  onPressed: _testingStt ? null : _testStt,
                  child: Text(_testingStt ? 'Listening…' : 'Test STT (3 s)'),
                ),
                if (_sttTestResult.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _sttTestResult,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 32),

          // ----------------------------------------------------------------
          // TTS section
          // ----------------------------------------------------------------
          _SectionHeader(title: 'Text to Speech', theme: theme),
          const SizedBox(height: 8),

          // TTS provider
          _DropdownTile<TtsProvider>(
            label: 'Provider',
            value: settings.ttsProvider,
            items: const {
              TtsProvider.os: 'Device (OS)',
              TtsProvider.server: 'Server TTS',
            },
            onChanged: (v) => _save(settings.copyWith(ttsProvider: v)),
          ),

          // Voice picker
          if (_ttsVoices.isNotEmpty)
            _DropdownTile<String>(
              label: 'Voice',
              value: _ttsVoices
                      .any((v) => v.name == settings.ttsVoiceName)
                  ? settings.ttsVoiceName
                  : _ttsVoices.first.name,
              items: {for (final v in _ttsVoices) v.name: v.toString()},
              onChanged: (v) => _save(settings.copyWith(ttsVoiceName: v)),
            ),

          // Speed
          _SliderTile(
            label: 'Speed',
            value: settings.ttsSpeed,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            format: (v) => '${v.toStringAsFixed(1)}×',
            onChanged: (v) => _save(settings.copyWith(ttsSpeed: v)),
          ),

          // Pitch
          _SliderTile(
            label: 'Pitch',
            value: settings.ttsPitch,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            format: (v) => '${v.toStringAsFixed(1)}×',
            onChanged: (v) => _save(settings.copyWith(ttsPitch: v)),
          ),

          // Auto-play
          SwitchListTile(
            title: const Text('Auto-play AI responses'),
            subtitle: const Text('Speak response when streaming completes'),
            value: settings.autoPlay,
            onChanged: (v) => _save(settings.copyWith(autoPlay: v)),
          ),

          // Streaming TTS
          SwitchListTile(
            title: const Text('Streaming TTS'),
            subtitle: const Text('Play first sentence before response completes'),
            value: settings.streamingTts,
            onChanged: (v) => _save(settings.copyWith(streamingTts: v)),
          ),

          // Test TTS
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonal(
              onPressed: _testingTts ? null : _testTts,
              child: Text(_testingTts ? 'Speaking…' : 'Test TTS'),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  const _DropdownTile({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: items.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: format(value),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              format(value),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
