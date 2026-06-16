import 'package:flutter/material.dart';

/// RecordingConsentBanner — Voice recording consent dialog for ɳClaw (S50-T14)
///
/// Displays a consent bottom sheet before any voice memo or transcription
/// session begins. User must explicitly tap "I consent" before recording starts.
/// Tapping "Decline" cancels the recording.
///
/// Usage:
///   final accepted = await RecordingConsentBanner.show(
///     context,
///     context: RecordingContext.voiceMemo,
///   );
///   if (accepted) startRecording();
///
/// Legal context:
///   - US all-party consent states (CA, FL, IL, etc.): all parties must consent.
///   - EU GDPR: explicit consent required before recording personal audio.
///   - See: https://nself.org/legal/recording-consent
enum RecordingContext {
  voiceMemo,
  voiceTranscription,
}

class RecordingConsentBanner extends StatelessWidget {
  final RecordingContext recordingContext;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const RecordingConsentBanner({
    super.key,
    this.recordingContext = RecordingContext.voiceMemo,
    required this.onAccept,
    required this.onDecline,
  });

  /// Convenience method to show as a modal bottom sheet.
  /// Returns true if the user consented, false if declined or dismissed.
  static Future<bool> show(
    BuildContext context, {
    RecordingContext recordingContext = RecordingContext.voiceMemo,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordingConsentBanner(
        recordingContext: recordingContext,
        onAccept: () => Navigator.of(context).pop(true),
        onDecline: () => Navigator.of(context).pop(false),
      ),
    );
    return result ?? false;
  }

  String get _contextLabel {
    switch (recordingContext) {
      case RecordingContext.voiceMemo:
        return 'voice memo';
      case RecordingContext.voiceTranscription:
        return 'voice transcription';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎙️', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 16),
          Text(
            'This session will be recorded',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Starting $_contextLabel will record and process your audio. '
            'Your consent is required before recording begins.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              // Open recording consent policy in browser
              // url_launcher is expected to be available in the app
              // launchUrl(Uri.parse('https://nself.org/legal/recording-consent'));
            },
            child: Text(
              'Recording Consent Policy · Privacy Policy',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: colorScheme.primary,
                  ),
                  child: const Text('I consent'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
