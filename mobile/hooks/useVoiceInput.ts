/**
 * useVoiceInput — voice recording + transcription state machine for nclaw/mobile.
 *
 * Purpose: Manages the full voice-input lifecycle: microphone permission gate,
 *          expo-av audio recording (press-hold), WAV/PCM read from disk,
 *          NativeNclaw.transcribe JSI call, and chat-input population.
 *
 * Inputs:  onTranscription(text: string) — called when transcription succeeds.
 *          onError(err: VoiceInputError) — called on permission denial or
 *          transcription failure.
 *
 * Outputs: VoiceInputState — { status, startRecording, stopRecording,
 *          cancelRecording, isPermissionGranted }.
 *
 * Constraints:
 *   - Audio format: LINEAR_PCM 16-bit 16 kHz mono (Whisper input format).
 *   - expo-av must be installed (peer dep).
 *   - getNcLawJSI().transcribe() must be registered before use (T-P3-E4-W2-S3-T03).
 *   - Recording state machine: idle → recording → transcribing → done → idle
 *     or idle → recording → cancelled → idle
 *     or any → error → idle.
 *   - Max recording duration: 60 s (auto-stop).
 *   - Min recording duration: 0.5 s (discard shorter clips).
 *
 * SPORT: none — component-only, no tracked entity.
 * Cross-ref: VoiceInput.tsx · T-P3-E4-W2-S3-T03 (transcribe JSI) · T-P3-E4-W2-S3-T07
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { Linking } from 'react-native';
import { Audio } from 'expo-av';
import * as FileSystem from 'expo-file-system';
import { getNcLawJSI } from '@nself/native-bridge';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Discriminated union for voice input status. */
export type VoiceStatus =
  | 'idle'
  | 'requesting_permission'
  | 'recording'
  | 'transcribing'
  | 'done'
  | 'error';

/** Error categories surfaced to the caller. */
export type VoiceInputErrorCode =
  | 'permission_denied'
  | 'recording_failed'
  | 'transcription_failed'
  | 'too_short'
  | 'too_long';

export interface VoiceInputError {
  code: VoiceInputErrorCode;
  message: string;
}

export interface VoiceInputState {
  /** Current state machine status. */
  status: VoiceStatus;
  /** Whether microphone permission has been granted. */
  isPermissionGranted: boolean;
  /** Non-null when status === 'error'. */
  error: VoiceInputError | null;
  /** Start recording. No-op if not idle. */
  startRecording: () => Promise<void>;
  /** Stop recording and trigger transcription. No-op if not recording. */
  stopRecording: () => Promise<void>;
  /** Discard the current recording. No-op if not recording. */
  cancelRecording: () => void;
  /** Open device Settings to the app's microphone permission page. */
  openMicrophoneSettings: () => void;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_DURATION_MS = 60_000;
const MIN_DURATION_MS = 500;

/**
 * expo-av Recording options for Whisper-compatible WAV/PCM output.
 * 16-bit linear PCM, 16 kHz, mono — matches libnclaw Whisper input requirements.
 */
const RECORDING_OPTIONS: Audio.RecordingOptions = {
  android: {
    extension: '.wav',
    outputFormat: Audio.AndroidOutputFormat.DEFAULT,
    audioEncoder: Audio.AndroidAudioEncoder.DEFAULT,
    sampleRate: 16_000,
    numberOfChannels: 1,
    bitRate: 256_000,
  },
  ios: {
    extension: '.wav',
    audioQuality: Audio.IOSAudioQuality.HIGH,
    outputFormat: Audio.IOSOutputFormat.LINEARPCM,
    sampleRate: 16_000,
    numberOfChannels: 1,
    bitRate: 256_000,
    linearPCMBitDepth: 16,
    linearPCMIsBigEndian: false,
    linearPCMIsFloat: false,
  },
  web: {
    mimeType: 'audio/wav',
    bitsPerSecond: 256_000,
  },
};

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export interface UseVoiceInputOptions {
  /** Called when transcription succeeds with the resulting text. */
  onTranscription: (text: string) => void;
  /** Called on any voice input error. */
  onError: (err: VoiceInputError) => void;
}

export function useVoiceInput({
  onTranscription,
  onError,
}: UseVoiceInputOptions): VoiceInputState {
  const [status, setStatus] = useState<VoiceStatus>('idle');
  const [isPermissionGranted, setIsPermissionGranted] = useState(false);
  const [error, setError] = useState<VoiceInputError | null>(null);

  const recordingRef = useRef<Audio.Recording | null>(null);
  const startTimeRef = useRef<number | null>(null);
  const autoStopTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const cancelledRef = useRef(false);

  // Check permission on mount (non-blocking — status gates the record button in UI)
  useEffect(() => {
    Audio.getPermissionsAsync()
      .then(({ granted }) => setIsPermissionGranted(granted))
      .catch(() => setIsPermissionGranted(false));

    return () => {
      // Cleanup on unmount: stop any active recording
      if (recordingRef.current) {
        recordingRef.current.stopAndUnloadAsync().catch(() => undefined);
        recordingRef.current = null;
      }
      if (autoStopTimerRef.current) {
        clearTimeout(autoStopTimerRef.current);
      }
    };
  }, []);

  // ------------------------------------------------------------------
  // Internal helpers
  // ------------------------------------------------------------------

  const emitError = useCallback(
    (code: VoiceInputErrorCode, message: string) => {
      const err: VoiceInputError = { code, message };
      setError(err);
      setStatus('error');
      onError(err);
    },
    [onError],
  );

  const resetToIdle = useCallback(() => {
    setStatus('idle');
    setError(null);
    cancelledRef.current = false;
  }, []);

  // ------------------------------------------------------------------
  // Public actions
  // ------------------------------------------------------------------

  const startRecording = useCallback(async (): Promise<void> => {
    if (status !== 'idle') return;

    cancelledRef.current = false;
    setError(null);

    // 1. Request microphone permission if not yet granted
    setStatus('requesting_permission');
    let permGranted = isPermissionGranted;
    if (!permGranted) {
      const { granted } = await Audio.requestPermissionsAsync();
      setIsPermissionGranted(granted);
      permGranted = granted;
    }

    if (!permGranted) {
      emitError(
        'permission_denied',
        'Microphone access denied. Please enable it in Settings.',
      );
      return;
    }

    // 2. Configure audio session
    try {
      await Audio.setAudioModeAsync({
        allowsRecordingIOS: true,
        playsInSilentModeIOS: true,
      });
    } catch {
      emitError('recording_failed', 'Failed to configure audio session.');
      return;
    }

    // 3. Start recording
    try {
      const recording = new Audio.Recording();
      await recording.prepareToRecordAsync(RECORDING_OPTIONS);
      await recording.startAsync();
      recordingRef.current = recording;
      startTimeRef.current = Date.now();
      setStatus('recording');

      // Auto-stop after MAX_DURATION_MS
      autoStopTimerRef.current = setTimeout(() => {
        stopRecording();
      }, MAX_DURATION_MS);
    } catch {
      emitError('recording_failed', 'Failed to start recording.');
    }
  }, [status, isPermissionGranted, emitError]);

  const stopRecording = useCallback(async (): Promise<void> => {
    if (status !== 'recording') return;
    if (!recordingRef.current) return;

    if (autoStopTimerRef.current) {
      clearTimeout(autoStopTimerRef.current);
      autoStopTimerRef.current = null;
    }

    const elapsedMs = startTimeRef.current
      ? Date.now() - startTimeRef.current
      : 0;

    const recording = recordingRef.current;
    recordingRef.current = null;

    // Validate duration before transcribing
    if (elapsedMs < MIN_DURATION_MS) {
      try {
        await recording.stopAndUnloadAsync();
      } catch {
        // ignore cleanup errors
      }
      emitError('too_short', 'Recording too short. Hold the button to record.');
      return;
    }

    setStatus('transcribing');

    // 1. Stop and get URI
    let uri: string | null | undefined;
    try {
      await recording.stopAndUnloadAsync();
      uri = recording.getURI();
    } catch {
      emitError('recording_failed', 'Failed to stop recording.');
      return;
    }

    if (!uri) {
      emitError('recording_failed', 'No audio file found after recording.');
      return;
    }

    if (cancelledRef.current) {
      // User cancelled after stop was triggered by auto-stop timer
      resetToIdle();
      return;
    }

    // 2. Read WAV bytes as base64 then convert to Uint8Array
    let audioData: Uint8Array;
    try {
      const base64 = await FileSystem.readAsStringAsync(uri, {
        encoding: FileSystem.EncodingType.Base64,
      });
      const binaryStr = atob(base64);
      audioData = new Uint8Array(binaryStr.length);
      for (let i = 0; i < binaryStr.length; i++) {
        audioData[i] = binaryStr.charCodeAt(i);
      }
    } catch {
      emitError('transcription_failed', 'Failed to read audio data.');
      return;
    }

    if (cancelledRef.current) {
      resetToIdle();
      return;
    }

    // 3. Call NativeNclaw.transcribe via JSI
    try {
      const text = await getNcLawJSI().transcribe(audioData);
      setStatus('done');
      setError(null);
      onTranscription(text);
      // Caller populates chat input; reset to idle after a tick so animations complete
      requestAnimationFrame(() => resetToIdle());
    } catch (err) {
      const message =
        err instanceof Error ? err.message : 'Transcription failed.';
      emitError('transcription_failed', message);
    }
  }, [status, onTranscription, emitError, resetToIdle]);

  const cancelRecording = useCallback((): void => {
    if (status !== 'recording') return;
    cancelledRef.current = true;

    if (autoStopTimerRef.current) {
      clearTimeout(autoStopTimerRef.current);
      autoStopTimerRef.current = null;
    }

    const recording = recordingRef.current;
    recordingRef.current = null;

    if (recording) {
      recording.stopAndUnloadAsync().catch(() => undefined);
    }

    resetToIdle();
  }, [status, resetToIdle]);

  const openMicrophoneSettings = useCallback((): void => {
    Linking.openSettings().catch(() => undefined);
  }, []);

  return {
    status,
    isPermissionGranted,
    error,
    startRecording,
    stopRecording,
    cancelRecording,
    openMicrophoneSettings,
  };
}
