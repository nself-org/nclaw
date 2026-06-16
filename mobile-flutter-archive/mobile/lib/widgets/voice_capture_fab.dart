/// E-26-08a: Voice capture FAB with long-press record.
///
/// Long-press to record, release to stop. Transcribes via STT,
/// then inserts draft text into the composer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/stt_service.dart';

/// Callback when transcription is complete.
typedef OnTranscribed = void Function(String text);

class VoiceCaptureFab extends ConsumerStatefulWidget {
  final OnTranscribed onTranscribed;

  const VoiceCaptureFab({super.key, required this.onTranscribed});

  @override
  ConsumerState<VoiceCaptureFab> createState() => _VoiceCaptureFabState();
}

class _VoiceCaptureFabState extends ConsumerState<VoiceCaptureFab>
    with SingleTickerProviderStateMixin {
  bool _recording = false;
  bool _transcribing = false;
  String _lastTranscript = '';
  late AnimationController _pulseController;
  final SttService _stt = SttService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _initStt();
  }

  Future<void> _initStt() async {
    _initialized = await _stt.initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!_initialized) {
      _initialized = await _stt.initialize();
      if (!_initialized) return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _recording = true;
      _lastTranscript = '';
    });
    _pulseController.repeat(reverse: true);

    await _stt.startListening(
      onResult: (transcript, isFinal) {
        _lastTranscript = transcript;
      },
    );
  }

  Future<void> _stopRecording() async {
    HapticFeedback.lightImpact();
    _pulseController.stop();
    _pulseController.reset();

    await _stt.stopListening();

    setState(() {
      _recording = false;
    });

    if (_lastTranscript.isNotEmpty) {
      HapticFeedback.mediumImpact();
      widget.onTranscribed(_lastTranscript);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_transcribing) {
      return Semantics(
        label: 'Transcribing voice input',
        liveRegion: true,
        child: FloatingActionButton(
          heroTag: 'voice_capture_fab',
          onPressed: null,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: _recording ? 'Recording — release to stop' : 'Voice input',
      hint: _recording ? null : 'Long-press and hold to record',
      button: true,
      child: GestureDetector(
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) => _stopRecording(),
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale =
                _recording ? 1.0 + (_pulseController.value * 0.15) : 1.0;
            return Transform.scale(
              scale: scale,
              child: FloatingActionButton(
                heroTag: 'voice_capture_fab',
                backgroundColor: _recording
                    ? theme.colorScheme.error
                    : theme.colorScheme.primaryContainer,
                onPressed: () {
                  if (!_recording) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Long-press and hold to record'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Icon(
                  _recording ? Icons.mic : Icons.mic_none,
                  color: _recording
                      ? theme.colorScheme.onError
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
