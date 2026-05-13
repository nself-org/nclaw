/// F-28-12: Sentry/GlitchTip crash reporting integration.
///
/// Initializes sentry_flutter with PII scrubbing. Reports only:
/// release version, OS, device model, stack traces.
/// DSN injected via --dart-define=SENTRY_DSN=...
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class CrashReportingService {
  /// The Sentry DSN, injected at build time via --dart-define.
  static const _dsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  /// Initialize Sentry with PII scrubbing.
  /// Wrap your app's runApp call:
  /// ```dart
  /// await CrashReportingService.init(() => runApp(MyApp()));
  /// ```
  static Future<void> init(FutureOr<void> Function() appRunner) async {
    if (_dsn.isEmpty) {
      // No DSN configured; skip Sentry init and just run the app.
      await appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;

        // Only report release, OS, device model, stack traces.
        // Scrub PII: no user emails, IPs, or identifiable data.
        options.sendDefaultPii = false;

        // Performance monitoring sample rate.
        options.tracesSampleRate = 0.2;

        // Attach screenshots on crash (non-PII widget tree).
        options.attachScreenshot = false;

        // Environment from build config.
        options.environment = const String.fromEnvironment(
          'SENTRY_ENVIRONMENT',
          defaultValue: 'production',
        );

        // Before-send callback to strip any remaining PII.
        options.beforeSend = _scrubEvent;
      },
      appRunner: appRunner,
    );
  }

  /// Report a non-fatal exception to Sentry.
  static Future<void> reportError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? context,
  }) async {
    if (_dsn.isEmpty) return;
    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      hint: context != null ? Hint.withMap({'context': context}) : null,
    );
  }

  /// Report a user feedback message.
  static Future<void> reportFeedback({
    required String message,
    String? email,
    String? name,
  }) async {
    if (_dsn.isEmpty) return;
    final eventId = await Sentry.captureMessage('User feedback');
    final feedback = SentryFeedback(
      message: message,
      associatedEventId: eventId,
      contactEmail: email,
      name: name,
    );
    await Sentry.captureFeedback(feedback);
  }

  /// Strip PII from events before sending.
  static FutureOr<SentryEvent?> _scrubEvent(
    SentryEvent event,
    Hint hint,
  ) {
    // Remove user IP address if somehow set.
    if (event.user != null) {
      event = event.copyWith(
        user: event.user?.copyWith(ipAddress: null, email: null, username: null),
      );
    }

    // Remove breadcrumbs that might contain PII (URLs with tokens, etc.).
    final cleanBreadcrumbs = event.breadcrumbs?.where((b) {
      final data = b.data;
      if (data != null && data.containsKey('url')) {
        final url = data['url']?.toString() ?? '';
        // Strip URLs containing tokens or keys.
        if (url.contains('token=') || url.contains('key=')) {
          return false;
        }
      }
      return true;
    }).toList();

    return event.copyWith(breadcrumbs: cleanBreadcrumbs);
  }
}
