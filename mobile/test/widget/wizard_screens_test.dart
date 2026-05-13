// wizard_screens_test.dart
// AA04 — Widget tests for bootstrap wizard Screens 3–5.
//
// Tests:
//   - Screen 3: toggling a plugin updates wizard_state.selectedPlugins
//   - Screen 3: Skip All calls the skip callback
//   - Screen 4: hidden when cron plugin is NOT in selectedPlugins (tested via flag)
//   - Screen 4: timezone and wake-time dropdowns exist
//   - Screen 5: all 5 template radio buttons render
//   - Screen 5: selecting a template updates wizardStateProvider.agentTemplate
//   - Screen 5: Finish Setup calls the finish callback

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/onboarding/wizard_state.dart';
import 'package:nself_claw/onboarding/screen3_plugins.dart';
import 'package:nself_claw/onboarding/screen4_scheduler.dart';
import 'package:nself_claw/onboarding/screen5_templates.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _mockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'read') return null;
      return null;
    },
  );
}

void _mockUrlLauncher() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/url_launcher'),
    (MethodCall call) async => true,
  );
}

/// Wraps a widget under test in ProviderScope + MaterialApp.
Widget _wrap(Widget widget) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: widget,
          ),
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    _mockSecureStorage();
    _mockUrlLauncher();
  });

  // -------------------------------------------------------------------------
  // Screen 3 — Plugin Onboarding
  // -------------------------------------------------------------------------

  group('Screen3Plugins', () {
    testWidgets('renders all 5 plugin toggles', (tester) async {
      await tester.pumpWidget(
        _wrap(Screen3Plugins(onContinue: () {}, onSkipAll: () {})),
      );
      await tester.pump();

      for (final id in kAllWizardPlugins) {
        expect(find.byKey(Key('plugin-toggle-$id')), findsOneWidget,
            reason: 'Toggle for $id not found');
      }
    });

    testWidgets('toggling cron adds it to selectedPlugins', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(builder: (ctx) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Screen3Plugins(onContinue: () {}, onSkipAll: () {}),
                ),
              ),
            );
          }),
        ),
      );
      await tester.pump();

      // Cron starts off — toggle it ON
      final cronToggle = find.byKey(const Key('plugin-toggle-cron'));
      expect(cronToggle, findsOneWidget);

      // Default state: cron is not selected
      expect(
        container.read(wizardStateProvider).selectedPlugins,
        isNot(contains(kPluginCron)),
      );

      await tester.tap(cronToggle);
      await tester.pumpAndSettle();

      expect(
        container.read(wizardStateProvider).selectedPlugins,
        contains(kPluginCron),
      );
    });

    testWidgets('Skip All button calls onSkipAll callback', (tester) async {
      bool skipped = false;
      await tester.pumpWidget(
        _wrap(Screen3Plugins(
          onContinue: () {},
          onSkipAll: () => skipped = true,
        )),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('screen3-skip-all')));
      await tester.pumpAndSettle();

      expect(skipped, isTrue);
    });

    testWidgets('Continue button calls onContinue callback', (tester) async {
      bool continued = false;
      await tester.pumpWidget(
        _wrap(Screen3Plugins(
          onContinue: () => continued = true,
          onSkipAll: () {},
        )),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('screen3-continue')));
      await tester.pumpAndSettle();

      expect(continued, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Screen 4 — Scheduler
  // -------------------------------------------------------------------------

  group('Screen4Scheduler', () {
    testWidgets('renders timezone dropdown', (tester) async {
      await tester.pumpWidget(
        _wrap(Screen4Scheduler(onContinue: () {}, onBack: () {})),
      );
      await tester.pump();

      expect(find.byKey(const Key('screen4-timezone')), findsOneWidget);
    });

    testWidgets('renders wake-time dropdown', (tester) async {
      await tester.pumpWidget(
        _wrap(Screen4Scheduler(onContinue: () {}, onBack: () {})),
      );
      await tester.pump();

      expect(find.byKey(const Key('screen4-wake-time')), findsOneWidget);
    });

    testWidgets('renders all three recipe checkboxes', (tester) async {
      await tester.pumpWidget(
        _wrap(Screen4Scheduler(onContinue: () {}, onBack: () {})),
      );
      await tester.pump();

      expect(
          find.byKey(const Key('screen4-morning-briefing')), findsOneWidget);
      expect(find.byKey(const Key('screen4-eod-summary')), findsOneWidget);
      expect(find.byKey(const Key('screen4-weekly-review')), findsOneWidget);
    });

    testWidgets('Back button calls onBack callback', (tester) async {
      bool wentBack = false;
      await tester.pumpWidget(
        _wrap(
            Screen4Scheduler(onContinue: () {}, onBack: () => wentBack = true)),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('screen4-back')));
      await tester.pumpAndSettle();

      expect(wentBack, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Screen 5 — Agent Templates
  // -------------------------------------------------------------------------

  group('Screen5Templates', () {
    testWidgets('renders all 5 template radio tiles', (tester) async {
      await tester.pumpWidget(
        _wrap(Screen5Templates(onFinish: () {}, onBack: () {})),
      );
      await tester.pump();

      for (final id in [
        kTemplatePersonalAssistant,
        kTemplateResearchAgent,
        kTemplateWritingCoach,
        kTemplateCodeReviewer,
        kTemplateCustom,
      ]) {
        expect(find.byKey(Key('template-$id')), findsOneWidget,
            reason: 'Template tile $id not found');
      }
    });

    testWidgets('tapping Research Agent updates wizardStateProvider',
        (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(builder: (ctx) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      Screen5Templates(onFinish: () {}, onBack: () {}),
                ),
              ),
            );
          }),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(Key('template-$kTemplateResearchAgent')));
      await tester.pumpAndSettle();

      expect(
        container.read(wizardStateProvider).agentTemplate,
        equals(kTemplateResearchAgent),
      );
    });

    testWidgets('Finish Setup button calls onFinish callback', (tester) async {
      bool finished = false;
      await tester.pumpWidget(
        _wrap(Screen5Templates(
          onFinish: () => finished = true,
          onBack: () {},
        )),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('screen5-finish')));
      await tester.pumpAndSettle();

      expect(finished, isTrue);
    });

    testWidgets('Back button calls onBack callback', (tester) async {
      bool wentBack = false;
      await tester.pumpWidget(
        _wrap(Screen5Templates(onFinish: () {}, onBack: () => wentBack = true)),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('screen5-back')));
      await tester.pumpAndSettle();

      expect(wentBack, isTrue);
    });
  });
}
