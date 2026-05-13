// T-1111: VoiceChatWidget — push-to-talk + tap-to-toggle + waveform.
//
// Replaces the chat input bar when voice mode is active. Two recording modes:
//   - Push-to-talk: hold button → record → release → put transcript in field
//   - Tap-to-toggle: tap to start, tap again to stop
//
// While recording, shows an animated 5-bar waveform, interim transcript
// bubble, MM:SS elapsed counter, and a cancel button.
//
// Waveform bars oscillate in amplitude driven by SpeechToText.soundLevel.
// Auto-send fires 1.5 s after the last speech (silence threshold).

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/stt_service.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// Floating voice-input overlay that sits above the keyboard area.
///
/// When [mode] is [VoiceInputMode.pushToTalk] the mic button responds to
/// long-press gestures. When it is [VoiceInputMode.tapToggle] a single tap
/// starts/stops recording.
///
/// [onTranscript] is called once the final transcript is ready (either on
/// release for PTT, or on stop for tap-toggle). [autoSendDelay] controls
/// how long after silence to fire [onAutoSend] (disabled when null).
class VoiceChatWidget extends StatefulWidget {
  final VoiceInputMode mode;
  final Duration autoSendDelay;
  final bool autoSend;

  /// Called with the final transcript text when recording ends.
  final ValueChanged<String> onTranscript;

  /// Called when auto-send fires. If null, auto-send is disabled.
  final VoidCallback? onAutoSend;

  const VoiceChatWidget({
    super.key,
    this.mode = VoiceInputMode.tapToggle,
    this.autoSendDelay = const Duration(milliseconds: 1500),
    this.autoSend = false,
    required this.onTranscript,
    this.onAutoSend,
  });

  @override
  State<VoiceChatWidget> createState() => _VoiceChatWidgetState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _VoiceChatWidgetState extends State<VoiceChatWidget>
    with TickerProviderStateMixin {
  final SttService _stt = SttService();

  bool _recording = false;
  bool _initializing = false;
  String _interimText = '';
  String _finalText = '';
  int _elapsedSeconds = 0;

  Timer? _elapsedTimer;
  Timer? _silenceTimer;

  // 5 animation controllers — one per waveform bar.
  late final List<AnimationController> _barControllers;
  late final List<Animation<double>> _barAnimations;

  static const int _barCount = 5;
  final Random _rand = Random();

  @override
  void initState() {
    super.initState();
    _barControllers = List.generate(_barCount, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + _rand.nextInt(200)),
      );
      ctrl.repeat(reverse: true);
      return ctrl;
    });
    _barAnimations = _barControllers.map((ctrl) {
      return Tween<double>(begin: 0.15, end: 1.0).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
      );
    }).toList();
    _initStt();
  }

  @override
  void dispose() {
    for (final c in _barControllers) {
      c.dispose();
    }
    _elapsedTimer?.cancel();
    _silenceTimer?.cancel();
    _stt.stopListening();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // STT init
  // -------------------------------------------------------------------------

  Future<void> _initStt() async {
    setState(() => _initializing = true);
    await _stt.initialize();
    setState(() => _initializing = false);
  }

  // -------------------------------------------------------------------------
  // Recording lifecycle
  // -------------------------------------------------------------------------

  Future<void> _startRecording() async {
    if (_recording || !_stt.isReady) return;
    setState(() {
      _recording = true;
      _interimText = '';
      _finalText = '';
      _elapsedSeconds = 0;
    });
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _elapsedSeconds++),
    );

    await _stt.startListening(
      onResult: (text, isFinal) {
        setState(() {
          _interimText = isFinal ? '' : text;
          if (isFinal) _finalText += (text.isNotEmpty ? text : '');
        });
        if (isFinal && text.isNotEmpty) {
          _resetSilenceTimer();
        }
      },
      onSoundLevel: (level) {
        // soundLevel is roughly –2..10 in practice — clamp to 0..1
        final normalised = ((level + 2) / 12).clamp(0.0, 1.0);
        _updateBarAmplitudes(normalised);
      },
      onDone: () {
        if (_recording) _stopRecording();
      },
    );
  }

  void _stopRecording({bool cancel = false}) {
    if (!_recording) return;
    _elapsedTimer?.cancel();
    _silenceTimer?.cancel();
    _stt.stopListening();
    final transcript = (_finalText + _interimText).trim();
    setState(() {
      _recording = false;
      _interimText = '';
      _finalText = '';
      _elapsedSeconds = 0;
    });
    if (!cancel && transcript.isNotEmpty) {
      widget.onTranscript(transcript);
    }
  }

  void _cancelRecording() => _stopRecording(cancel: true);

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    if (widget.autoSend && widget.onAutoSend != null) {
      _silenceTimer = Timer(widget.autoSendDelay, () {
        _stopRecording();
        widget.onAutoSend!();
      });
    }
  }

  void _updateBarAmplitudes(double level) {
    for (int i = 0; i < _barCount; i++) {
      final target = (level * (0.4 + _rand.nextDouble() * 0.6)).clamp(0.15, 1.0);
      _barControllers[i].animateTo(
        target,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Gesture handlers
  // -------------------------------------------------------------------------

  void _onTap() {
    if (widget.mode != VoiceInputMode.tapToggle) return;
    if (_recording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _onLongPressStart(LongPressStartDetails _) {
    if (widget.mode != VoiceInputMode.pushToTalk) return;
    _startRecording();
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (widget.mode != VoiceInputMode.pushToTalk) return;
    _stopRecording();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ----------------------------------------------------------------
            // Interim transcript bubble (only while recording)
            // ----------------------------------------------------------------
            if (_recording && _interimText.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _interimText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // ----------------------------------------------------------------
            // Controls row
            // ----------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Cancel button (only while recording)
                if (_recording)
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: colorScheme.error,
                    tooltip: 'Cancel',
                    onPressed: _cancelRecording,
                  )
                else
                  const SizedBox(width: 48),

                const SizedBox(width: 8),

                // Waveform + mic button
                GestureDetector(
                  onTap: _onTap,
                  onLongPressStart: _onLongPressStart,
                  onLongPressEnd: _onLongPressEnd,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _recording
                          ? colorScheme.errorContainer
                          : colorScheme.primaryContainer,
                      boxShadow: _recording
                          ? [
                              BoxShadow(
                                color: colorScheme.error.withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                    child: _recording
                        ? _WaveformBars(
                            animations: _barAnimations,
                            color: colorScheme.onErrorContainer,
                          )
                        : Icon(
                            widget.mode == VoiceInputMode.pushToTalk
                                ? Icons.mic
                                : Icons.mic_none,
                            size: 36,
                            color: colorScheme.onPrimaryContainer,
                          ),
                  ),
                ),

                const SizedBox(width: 8),

                // Elapsed counter (only while recording)
                if (_recording)
                  SizedBox(
                    width: 48,
                    child: Text(
                      _formatElapsed(_elapsedSeconds),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),

            // ----------------------------------------------------------------
            // Mode hint
            // ----------------------------------------------------------------
            if (!_recording)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.mode == VoiceInputMode.pushToTalk
                      ? 'Hold to record'
                      : _initializing
                          ? 'Initialising…'
                          : 'Tap to record',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Waveform bars
// ---------------------------------------------------------------------------

class _WaveformBars extends StatelessWidget {
  final List<Animation<double>> animations;
  final Color color;

  const _WaveformBars({required this.animations, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(animations),
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(animations.length, (i) {
            const maxBarHeight = 32.0;
            const barWidth = 4.0;
            const spacing = 3.0;

            return Container(
              width: barWidth,
              height: maxBarHeight * animations[i].value,
              margin: const EdgeInsets.symmetric(horizontal: spacing / 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(barWidth / 2),
              ),
            );
          }),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Mic button for use in the InputBar (opens VoiceChatWidget overlay)
// ---------------------------------------------------------------------------

/// Mic icon button that can be embedded in the chat input bar.
/// Tapping opens a modal bottom sheet containing [VoiceChatWidget].
class VoiceMicButton extends StatelessWidget {
  final VoiceInputMode mode;
  final bool autoSend;
  final Duration autoSendDelay;
  final ValueChanged<String> onTranscript;
  final VoidCallback? onAutoSend;

  const VoiceMicButton({
    super.key,
    this.mode = VoiceInputMode.tapToggle,
    this.autoSend = false,
    this.autoSendDelay = const Duration(milliseconds: 1500),
    required this.onTranscript,
    this.onAutoSend,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.mic_none),
      tooltip: 'Voice input',
      onPressed: () => _openOverlay(context),
    );
  }

  void _openOverlay(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => VoiceChatWidget(
        mode: mode,
        autoSend: autoSend,
        autoSendDelay: autoSendDelay,
        onTranscript: (text) {
          Navigator.of(context).pop();
          onTranscript(text);
        },
        onAutoSend: onAutoSend != null
            ? () {
                Navigator.of(context).pop();
                onAutoSend!();
              }
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Enum
// ---------------------------------------------------------------------------

enum VoiceInputMode {
  /// Hold the button to record; release to stop.
  pushToTalk,

  /// Tap once to start recording; tap again to stop.
  tapToggle,
}
