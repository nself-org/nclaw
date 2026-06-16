/**
 * VoiceInput — voice recording UI component for nclaw/mobile chat screen.
 *
 * Purpose: Renders the microphone button, animated waveform during recording,
 *          transcription spinner, and error/permission-denied states.
 *          Delegates all recording/transcription logic to useVoiceInput hook.
 *
 * Inputs:  onTranscription(text: string) — parent receives the transcribed text
 *          to populate the chat input field.
 *          style? — optional ViewStyle for the outer container.
 *
 * Outputs: Renders one of five visual states:
 *          idle         — mic button (tap to start)
 *          recording    — animated waveform bars + cancel button
 *          transcribing — spinner
 *          error/denied — inline message + settings link (for permission denial)
 *          done         — instant transition back to idle (no visible state)
 *
 * Constraints:
 *   - Interaction: press-and-hold mic button to record; release to transcribe.
 *     Tap-cancel button to discard.
 *   - Waveform animation: 5 bars, staggered Animated.loop on scaleY + opacity.
 *   - No network calls — all transcription is on-device via libnclaw Whisper.
 *   - Does not manage chat input state — parent owns the input value.
 *   - WCAG 2.1 AA: all interactive elements have accessibilityLabel.
 *
 * SPORT: none — component-only, no tracked entity.
 * Cross-ref: useVoiceInput.ts · T-P3-E4-W2-S3-T07 · T-P3-E4-W2-S3-T03
 */

import React, { useCallback, useEffect, useRef } from 'react';
import {
  Animated,
  Easing,
  Pressable,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  ViewStyle,
} from 'react-native';

import {
  useVoiceInput,
  type VoiceInputError,
  type VoiceStatus,
} from '../hooks/useVoiceInput';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface VoiceInputProps {
  /** Called when transcription succeeds — populate the chat input with this text. */
  onTranscription: (text: string) => void;
  /** Optional outer container style. */
  style?: ViewStyle;
}

// ---------------------------------------------------------------------------
// Waveform bar count
// ---------------------------------------------------------------------------

const BAR_COUNT = 5;

// ---------------------------------------------------------------------------
// WaveformBars — animated waveform displayed during recording
// ---------------------------------------------------------------------------

interface WaveformBarsProps {
  isActive: boolean;
}

function WaveformBars({ isActive }: WaveformBarsProps): React.ReactElement {
  const animations = useRef(
    Array.from({ length: BAR_COUNT }, () => new Animated.Value(0.3)),
  ).current;
  const loops = useRef<Animated.CompositeAnimation[]>([]);

  useEffect(() => {
    if (isActive) {
      // Start staggered loop animations for each bar
      loops.current = animations.map((anim, index) =>
        Animated.loop(
          Animated.sequence([
            Animated.delay(index * 80),
            Animated.timing(anim, {
              toValue: 1,
              duration: 300,
              easing: Easing.inOut(Easing.ease),
              useNativeDriver: true,
            }),
            Animated.timing(anim, {
              toValue: 0.3,
              duration: 300,
              easing: Easing.inOut(Easing.ease),
              useNativeDriver: true,
            }),
          ]),
        ),
      );
      loops.current.forEach((loop) => loop.start());
    } else {
      // Stop all loops and reset to resting position
      loops.current.forEach((loop) => loop.stop());
      animations.forEach((anim) =>
        Animated.timing(anim, {
          toValue: 0.3,
          duration: 150,
          useNativeDriver: true,
        }).start(),
      );
    }
    return () => {
      loops.current.forEach((loop) => loop.stop());
    };
  }, [isActive, animations]);

  return (
    <View style={styles.waveformContainer} accessibilityLabel="Recording waveform">
      {animations.map((scaleY, index) => (
        <Animated.View
          key={index}
          style={[
            styles.waveformBar,
            {
              transform: [{ scaleY }],
              opacity: scaleY,
            },
          ]}
        />
      ))}
    </View>
  );
}

// ---------------------------------------------------------------------------
// VoiceInput — main component
// ---------------------------------------------------------------------------

export function VoiceInput({
  onTranscription,
  style,
}: VoiceInputProps): React.ReactElement {
  const handleError = useCallback((_err: VoiceInputError) => {
    // Errors are surfaced via hook state — no extra side-effect needed here
  }, []);

  const {
    status,
    isPermissionGranted,
    error,
    startRecording,
    stopRecording,
    cancelRecording,
    openMicrophoneSettings,
  } = useVoiceInput({ onTranscription, onError: handleError });

  // ------------------------------------------------------------------
  // Derived booleans
  // ------------------------------------------------------------------

  const isRecording = status === 'recording';
  const isTranscribing = status === 'transcribing';
  const isError = status === 'error';
  const isPermissionDenied = isError && error?.code === 'permission_denied';
  const isIdle = status === 'idle' || status === 'done';

  // ------------------------------------------------------------------
  // Render: permission denied state
  // ------------------------------------------------------------------

  if (isPermissionDenied) {
    return (
      <View style={[styles.container, style]}>
        <View style={styles.errorRow}>
          <Text style={styles.errorText} accessibilityRole="alert">
            Microphone access denied.
          </Text>
          <TouchableOpacity
            onPress={openMicrophoneSettings}
            accessibilityLabel="Open Settings to enable microphone access"
            accessibilityRole="button"
            style={styles.settingsLink}
          >
            <Text style={styles.settingsLinkText}>Open Settings</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // ------------------------------------------------------------------
  // Render: non-critical error toast (transcription failed, too short, etc.)
  // ------------------------------------------------------------------

  if (isError && !isPermissionDenied) {
    return (
      <View style={[styles.container, style]}>
        <Text
          style={styles.errorText}
          accessibilityRole="alert"
          numberOfLines={2}
        >
          {error?.message ?? 'Voice input failed. Try again.'}
        </Text>
      </View>
    );
  }

  // ------------------------------------------------------------------
  // Render: transcribing spinner
  // ------------------------------------------------------------------

  if (isTranscribing) {
    return (
      <View style={[styles.container, style]}>
        <TranscriptionSpinner />
      </View>
    );
  }

  // ------------------------------------------------------------------
  // Render: recording state — waveform + cancel button
  // ------------------------------------------------------------------

  if (isRecording) {
    return (
      <View style={[styles.container, style]}>
        <View style={styles.recordingRow}>
          <WaveformBars isActive />
          <TouchableOpacity
            onPress={cancelRecording}
            style={styles.cancelButton}
            accessibilityLabel="Cancel recording"
            accessibilityRole="button"
          >
            <Text style={styles.cancelButtonText}>Cancel</Text>
          </TouchableOpacity>
          {/* Releasing the press over the mic button triggers stopRecording.
              The outer Pressable handles the release event. */}
          <Pressable
            onPress={stopRecording}
            style={styles.stopButton}
            accessibilityLabel="Stop recording and transcribe"
            accessibilityRole="button"
          >
            <View style={styles.stopDot} />
          </Pressable>
        </View>
      </View>
    );
  }

  // ------------------------------------------------------------------
  // Render: idle — mic button (hold to record)
  // ------------------------------------------------------------------

  return (
    <View style={[styles.container, style]}>
      <Pressable
        onLongPress={startRecording}
        onPress={isPermissionGranted ? startRecording : openMicrophoneSettings}
        delayLongPress={0}
        style={({ pressed }) => [
          styles.micButton,
          pressed && styles.micButtonPressed,
          !isIdle && styles.micButtonDisabled,
        ]}
        accessibilityLabel={
          isPermissionGranted
            ? 'Hold to record voice input'
            : 'Tap to enable microphone access'
        }
        accessibilityRole="button"
        disabled={!isIdle}
      >
        <MicIcon />
      </Pressable>
    </View>
  );
}

// ---------------------------------------------------------------------------
// TranscriptionSpinner — inline activity indicator
// ---------------------------------------------------------------------------

function TranscriptionSpinner(): React.ReactElement {
  const rotation = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const anim = Animated.loop(
      Animated.timing(rotation, {
        toValue: 1,
        duration: 800,
        easing: Easing.linear,
        useNativeDriver: true,
      }),
    );
    anim.start();
    return () => anim.stop();
  }, [rotation]);

  const spin = rotation.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg'],
  });

  return (
    <View style={styles.spinnerContainer}>
      <Animated.View
        style={[styles.spinner, { transform: [{ rotate: spin }] }]}
        accessibilityLabel="Transcribing"
      />
      <Text style={styles.transcribingLabel}>Transcribing…</Text>
    </View>
  );
}

// ---------------------------------------------------------------------------
// MicIcon — minimal SVG-free mic representation using Views
// ---------------------------------------------------------------------------

function MicIcon(): React.ReactElement {
  return (
    <View style={styles.micIconOuter}>
      <View style={styles.micIconInner} />
    </View>
  );
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const BRAND_PRIMARY = '#6C63FF';
const BRAND_ERROR = '#E53935';
const BRAND_TEXT_SECONDARY = '#888';
const BRAND_WHITE = '#FFF';
const BRAND_LINK = '#2196F3';

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 44,
  },

  // Mic button
  micButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: BRAND_PRIMARY,
    alignItems: 'center',
    justifyContent: 'center',
  },
  micButtonPressed: {
    opacity: 0.75,
    transform: [{ scale: 0.95 }],
  },
  micButtonDisabled: {
    opacity: 0.4,
  },

  // Mic icon (filled circle + smaller inner rect to hint mic shape)
  micIconOuter: {
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: BRAND_WHITE,
    alignItems: 'center',
    justifyContent: 'center',
  },
  micIconInner: {
    width: 8,
    height: 12,
    borderRadius: 4,
    backgroundColor: BRAND_PRIMARY,
  },

  // Recording row
  recordingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },

  // Waveform
  waveformContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 32,
    gap: 3,
  },
  waveformBar: {
    width: 4,
    height: 28,
    borderRadius: 2,
    backgroundColor: BRAND_PRIMARY,
  },

  // Cancel button
  cancelButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: BRAND_TEXT_SECONDARY,
  },
  cancelButtonText: {
    fontSize: 14,
    color: BRAND_TEXT_SECONDARY,
  },

  // Stop button
  stopButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: BRAND_ERROR,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stopDot: {
    width: 14,
    height: 14,
    borderRadius: 3,
    backgroundColor: BRAND_WHITE,
  },

  // Spinner
  spinnerContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  spinner: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: BRAND_PRIMARY,
    borderTopColor: 'transparent',
  },
  transcribingLabel: {
    fontSize: 14,
    color: BRAND_TEXT_SECONDARY,
  },

  // Error states
  errorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  errorText: {
    fontSize: 13,
    color: BRAND_ERROR,
    flexShrink: 1,
  },
  settingsLink: {
    paddingHorizontal: 4,
  },
  settingsLinkText: {
    fontSize: 13,
    color: BRAND_LINK,
    textDecorationLine: 'underline',
  },
});
