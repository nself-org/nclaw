// T-1110: Text-to-speech service wrapping the flutter_tts package.
// T-1117: Optional server TTS via POST /voice/synthesize (nself-voice plugin).
//
// Provides iOS (AVSpeechSynthesizer), Android (TextToSpeech), and macOS
// (NSSpeechSynthesizer) TTS. Markdown is stripped before speaking.
// When [serverUrl] is set, calls /voice/synthesize and plays the audio file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Metadata for a single TTS voice.
class VoiceInfo {
  final String name;
  final String locale;

  const VoiceInfo({required this.name, required this.locale});

  @override
  String toString() => '$name ($locale)';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Manages text-to-speech via the platform TTS engine.
///
/// Call [initialize] once before [speak]. Platform engines are available
/// without additional permissions on all three target platforms.
///
/// ```dart
/// final tts = TtsService();
/// await tts.initialize();
/// await tts.speak('Hello world');
/// await tts.stop();
/// ```
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// When set, TTS is routed to POST [serverUrl]/voice/synthesize.
  String? serverUrl;

  /// Voice name for server TTS requests.
  String? serverVoice;

  /// Speed for server TTS requests (1.0 = normal).
  double serverSpeed = 1.0;

  /// Whether the service has been initialised successfully.
  bool get isReady => _ready;

  // -------------------------------------------------------------------------
  // Markdown stripping
  // -------------------------------------------------------------------------

  /// Strip Markdown formatting from [text] before it is spoken.
  ///
  /// Removes:
  /// - Fenced code blocks (``` ... ```)
  /// - Inline code (`...`)
  /// - Bold/italic markers (**text** / *text* / __text__ / _text_)
  /// - Heading markers (# text)
  /// - Link syntax ([text](url)) → keeps link text
  /// - Image syntax (![alt](url)) → removes entirely
  /// - Horizontal rules (---, ***)
  /// - Bullet/numbered list markers
  static String stripMarkdown(String text) {
    // Remove fenced code blocks.
    var result = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // Remove inline code.
    result = result.replaceAll(RegExp(r'`[^`]*`'), '');
    // Remove image syntax (before link so it doesn't partially match).
    result = result.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '');
    // Replace link syntax [text](url) → text.
    result = result.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1');
    // Remove bold (**text** or __text__).
    result = result.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
    result = result.replaceAll(RegExp(r'__(.+?)__'), r'$1');
    // Remove italic (*text* or _text_).
    result = result.replaceAll(RegExp(r'\*(.+?)\*'), r'$1');
    result = result.replaceAll(RegExp(r'_(.+?)_'), r'$1');
    // Remove heading markers.
    result = result.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    // Remove horizontal rules.
    result = result.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');
    // Remove bullet/numbered list markers.
    result = result.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
    // Collapse multiple blank lines.
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Initialise the platform TTS engine with sensible defaults.
  Future<void> initialize() async {
    await _tts.setSharedInstance(true);
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ready = true;
  }

  /// Speak [text], stripping any Markdown formatting first.
  ///
  /// If the engine is already speaking, the current utterance is stopped
  /// before the new one starts. When [serverUrl] is set, audio is fetched
  /// from POST [serverUrl]/voice/synthesize and played as an MP3 file.
  Future<void> speak(String text) async {
    if (!_ready) return;
    final clean = stripMarkdown(text);
    if (clean.isEmpty) return;
    await _tts.stop();
    if (serverUrl != null && serverUrl!.isNotEmpty) {
      await _speakViaServer(clean);
    } else {
      await _tts.speak(clean);
    }
  }

  /// Synthesize [text] via the nself-voice server and play the resulting MP3.
  ///
  /// Falls back to the platform TTS engine on any network or server error.
  Future<void> _speakViaServer(String text) async {
    try {
      final body = jsonEncode({
        'text': text,
        if (serverVoice != null) 'voice': serverVoice,
        'speed': serverSpeed,
      });
      final response = await http
          .post(
            Uri.parse('$serverUrl/voice/synthesize'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        await _tts.speak(text);
        return;
      }
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File(
        '${tmpDir.path}/nself_voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await tmpFile.writeAsBytes(response.bodyBytes);
      await _tts.speak(tmpFile.path);
    } catch (_) {
      await _tts.speak(text);
    }
  }

  /// Stop the current utterance immediately.
  Future<void> stop() async {
    if (!_ready) return;
    await _tts.stop();
  }

  /// Pause the current utterance (iOS/macOS only; no-op on Android).
  Future<void> pause() async {
    if (!_ready) return;
    await _tts.pause();
  }

  /// Set the speech rate (0.0 = slowest, 1.0 = fastest; default 0.5).
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate.clamp(0.0, 1.0));
  }

  /// Set the TTS voice by [name]. No-op if the voice is unavailable.
  Future<void> setVoice(String name) async {
    if (!_ready) return;
    await _tts.setVoice({'name': name, 'locale': 'en-US'});
  }

  /// Return all available voices on the current device.
  Future<List<VoiceInfo>> getAvailableVoices() async {
    if (!_ready) return const [];
    try {
      final raw = await _tts.getVoices as List<dynamic>?;
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map((v) => VoiceInfo(
                name: v['name'] as String? ?? '',
                locale: v['locale'] as String? ?? '',
              ))
          .where((v) => v.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Register a callback fired when an utterance completes naturally.
  void onComplete(void Function() callback) {
    _tts.setCompletionHandler(callback);
  }

  /// Register a callback fired on TTS errors.
  void onError(void Function(String message) callback) {
    _tts.setErrorHandler((msg) => callback(msg.toString()));
  }
}
