// T-1113: Continuous voice conversation mode — full-screen hands-free loop.
//
// Flow:
//   listen → interim transcript → 1.5 s silence → auto-send
//   → AI streams response → TTS sentence-by-sentence → auto-listen again
//
// Interrupt: tap waveform/anywhere → stop TTS → start listening.
// Exit: X button or speaking "stop" / "goodbye".
// UI: black background, large waveform, small transcript bubble.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Full-screen overlay for hands-free voice conversation.
///
/// Open by long-pressing the mic button in [ChatScreen]. Close with
/// the X button or by saying "stop" / "goodbye".
class VoiceConversationScreen extends ConsumerStatefulWidget {
  const VoiceConversationScreen({super.key});

  @override
  ConsumerState<VoiceConversationScreen> createState() =>
      _VoiceConversationScreenState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum _ConvPhase {
  idle,
  listening,
  processing,
  speaking,
}

class _VoiceConversationScreenState
    extends ConsumerState<VoiceConversationScreen>
    with TickerProviderStateMixin {
  final SttService _stt = SttService();
  final TtsService _tts = TtsService();

  _ConvPhase _phase = _ConvPhase.idle;
  String _interimText = '';
  String _lastUserText = '';
  String _lastAssistantText = '';

  Timer? _silenceTimer;
  final List<String> _ttsSentenceQueue = [];

  // Waveform animation — 5 bars.
  late final List<AnimationController> _barControllers;
  late final List<Animation<double>> _barAnimations;
  static const int _barCount = 5;
  final Random _rand = Random();

  static const Duration _silenceDelay = Duration(milliseconds: 1500);
  static final RegExp _sentenceEnd = RegExp(r'(?<=[.!?])\s+');
  static final RegExp _exitPhrases =
      RegExp(r'\b(stop|goodbye|exit|close|quit)\b', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _barControllers = List.generate(_barCount, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 280 + _rand.nextInt(180)),
      )..repeat(reverse: true);
      return ctrl;
    });
    _barAnimations = _barControllers.map((ctrl) {
      return Tween<double>(begin: 0.1, end: 0.9).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
      );
    }).toList();

    _initAndStart();
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    for (final c in _barControllers) {
      c.dispose();
    }
    _stt.stopListening();
    _tts.stop();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Init
  // -------------------------------------------------------------------------

  Future<void> _initAndStart() async {
    await _stt.initialize();
    await _tts.initialize();
    _tts.onComplete(_onTtsComplete);
    _tts.onError((_) => _startListening());
    _startListening();
  }

  // -------------------------------------------------------------------------
  // Listening phase
  // -------------------------------------------------------------------------

  Future<void> _startListening() async {
    if (!mounted) return;
    await _tts.stop();
    _ttsSentenceQueue.clear();
    _silenceTimer?.cancel();
    setState(() {
      _phase = _ConvPhase.listening;
      _interimText = '';
    });

    await _stt.startListening(
      onResult: _onSttResult,
      onSoundLevel: _updateWaveform,
      onDone: () {
        if (_phase == _ConvPhase.listening) _onSilence();
      },
    );
  }

  void _onSttResult(String text, bool isFinal) {
    if (!mounted) return;
    setState(() => _interimText = text);

    // Exit phrase detection.
    if (_exitPhrases.hasMatch(text)) {
      _exit();
      return;
    }

    if (isFinal && text.isNotEmpty) {
      // Reset silence timer on each final word.
      _silenceTimer?.cancel();
      _silenceTimer = Timer(_silenceDelay, _onSilence);
    }
  }

  void _onSilence() {
    final text = _interimText.trim();
    if (text.isEmpty) {
      // Nothing heard — keep listening.
      _startListening();
      return;
    }
    _sendTranscript(text);
  }

  // -------------------------------------------------------------------------
  // Processing phase
  // -------------------------------------------------------------------------

  Future<void> _sendTranscript(String text) async {
    if (!mounted) return;
    await _stt.stopListening();
    setState(() {
      _phase = _ConvPhase.processing;
      _lastUserText = text;
      _interimText = '';
    });

    final serverUrl =
        ref.read(connectionProvider).activeServer?.url ?? '';
    ref.read(chatProvider.notifier).sendMessage(text, serverUrl);

    // Watch for streaming to complete.
    ref.listenManual<bool>(
      chatProvider.select((s) => s.isStreaming),
      (prev, current) {
        if (prev == true && current == false && mounted) {
          final msgs = ref.read(chatProvider).messages;
          final last = msgs.lastWhere(
            (m) => m.role == 'assistant',
            orElse: () => msgs.last,
          );
          if (last.role == 'assistant') {
            _speakResponse(last.content);
          } else {
            _startListening();
          }
        }
      },
      fireImmediately: false,
    );
  }

  // -------------------------------------------------------------------------
  // Speaking phase
  // -------------------------------------------------------------------------

  void _speakResponse(String text) {
    if (!mounted) return;
    setState(() {
      _phase = _ConvPhase.speaking;
      _lastAssistantText = text;
    });

    final sentences = text
        .split(_sentenceEnd)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (sentences.isEmpty) {
      _startListening();
      return;
    }

    _ttsSentenceQueue
      ..clear()
      ..addAll(sentences.skip(1));
    _tts.speak(sentences.first);
  }

  void _onTtsComplete() {
    if (_ttsSentenceQueue.isNotEmpty) {
      _tts.speak(_ttsSentenceQueue.removeAt(0));
    } else {
      // All sentences spoken — listen again.
      _startListening();
    }
  }

  // -------------------------------------------------------------------------
  // Interrupt + exit
  // -------------------------------------------------------------------------

  void _onTap() {
    if (_phase == _ConvPhase.speaking) {
      // Interrupt TTS → start listening immediately.
      _startListening();
    }
    // Tapping during listening/processing is a no-op.
  }

  void _exit() {
    _stt.stopListening();
    _tts.stop();
    if (mounted) Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------------
  // Waveform
  // -------------------------------------------------------------------------

  void _updateWaveform(double level) {
    if (!mounted) return;
    final normalised = ((level + 2) / 12).clamp(0.0, 1.0);
    for (int i = 0; i < _barCount; i++) {
      _barControllers[i].animateTo(
        (normalised * (0.4 + _rand.nextDouble() * 0.6)).clamp(0.1, 1.0),
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: Stack(
            children: [
              // Exit button
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                  tooltip: 'Exit',
                  onPressed: _exit,
                ),
              ),

              // Main content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Phase label
                    Text(
                      _phaseLabel(),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Waveform
                    _buildWaveform(),

                    const SizedBox(height: 32),

                    // Transcript bubble
                    if (_transcriptText().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _transcriptText(),
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _phase == _ConvPhase.listening
                                  ? Colors.white70
                                  : Colors.white38,
                              fontSize: 14,
                              fontStyle: _phase == _ConvPhase.listening
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                      ),

                    if (_phase == _ConvPhase.speaking)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Tap to interrupt',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    final active = _phase == _ConvPhase.listening || _phase == _ConvPhase.speaking;
    return AnimatedBuilder(
      animation: Listenable.merge(_barControllers),
      builder: (context, wf) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_barCount, (i) {
            const maxH = 64.0;
            const w = 6.0;
            final h = active ? maxH * _barAnimations[i].value : 8.0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: w,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _barColor(i),
                borderRadius: BorderRadius.circular(w / 2),
              ),
            );
          }),
        );
      },
    );
  }

  Color _barColor(int i) {
    if (_phase == _ConvPhase.speaking) return Colors.indigo.shade300;
    if (_phase == _ConvPhase.listening) return Colors.white70;
    if (_phase == _ConvPhase.processing) return Colors.white24;
    return Colors.white12;
  }

  String _phaseLabel() {
    switch (_phase) {
      case _ConvPhase.idle:
        return 'STARTING';
      case _ConvPhase.listening:
        return 'LISTENING';
      case _ConvPhase.processing:
        return 'THINKING';
      case _ConvPhase.speaking:
        return 'SPEAKING';
    }
  }

  String _transcriptText() {
    switch (_phase) {
      case _ConvPhase.listening:
        return _interimText;
      case _ConvPhase.processing:
        return _lastUserText;
      case _ConvPhase.speaking:
        return _lastAssistantText;
      case _ConvPhase.idle:
        return '';
    }
  }
}
