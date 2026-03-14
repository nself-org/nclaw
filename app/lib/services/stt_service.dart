// T-1109: Speech-to-text service wrapping the speech_to_text package.
//
// Provides a thin abstraction for microphone-based speech recognition on
// iOS, Android, and macOS. Permissions are requested on [initialize].

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// An available recognition locale.
class SttLocale {
  final String id;
  final String name;

  const SttLocale({required this.id, required this.name});
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Manages speech recognition via the platform STT engine.
///
/// Usage:
/// ```dart
/// final stt = SttService();
/// await stt.initialize();                          // once on startup
/// await stt.startListening(onResult: print);       // start capture
/// await stt.stopListening();                       // stop capture
/// ```
class SttService {
  final SpeechToText _stt = SpeechToText();

  bool _ready = false;

  /// Whether the service has been successfully initialised.
  bool get isReady => _ready;

  /// Whether recognition is currently active.
  bool get isListening => _stt.isListening;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Request microphone + speech-recognition permissions and initialise the
  /// platform engine.
  ///
  /// Must be called once before [startListening]. Returns `true` on success.
  Future<bool> initialize() async {
    // Request microphone permission.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;

    // speech_to_text uses its own internal permission handling on iOS/macOS;
    // we still guard with permission_handler for Android.
    _ready = await _stt.initialize(
      onError: (error) {
        // Errors surface via the onError callback in startListening.
        _ready = false;
      },
      onStatus: (_) {},
    );
    return _ready;
  }

  /// Returns the list of available recognition locales for the current
  /// device. Falls back to a single en-US entry if the engine returns none.
  Future<List<SttLocale>> getLocales() async {
    if (!_ready) return [const SttLocale(id: 'en-US', name: 'English (US)')];
    final raw = await _stt.locales();
    if (raw.isEmpty) return [const SttLocale(id: 'en-US', name: 'English (US)')];
    return raw
        .map((l) => SttLocale(id: l.localeId, name: l.name))
        .toList();
  }

  /// Start continuous speech recognition.
  ///
  /// [onResult] receives the latest transcript (may be interim).
  /// [onDone]   called when the session ends naturally (e.g. silence timeout).
  /// [onError]  called on recognition errors.
  /// [locale]   BCP-47 locale tag; defaults to en-US.
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onResult,
    void Function()? onDone,
    void Function(String error)? onError,
    String locale = 'en-US',
  }) async {
    if (!_ready || _stt.isListening) return;

    await _stt.listen(
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      localeId: locale,
      listenOptions: SpeechListenOptions(
        onDevice: false,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      ),
    );

    // SpeechToText does not expose a direct onDone; monitor status instead.
    if (onDone != null || onError != null) {
      _stt.statusListener = (status) {
        if (status == SpeechToText.notListeningStatus) {
          onDone?.call();
        }
        if (status == SpeechToText.doneStatus) {
          onDone?.call();
        }
      };
      _stt.errorListener = (error) {
        onError?.call(error.errorMsg);
      };
    }
  }

  /// Stop an active recognition session.
  Future<void> stopListening() async {
    if (_stt.isListening) await _stt.stop();
  }

  /// Cancel the current recognition session without firing [onDone].
  Future<void> cancelListening() async {
    if (_stt.isListening) await _stt.cancel();
  }
}
