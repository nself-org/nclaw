// T-1070: Widget tests for OnboardingScreen and ModelStatusCard.
//
// Tests:
//   - OnboardingScreen step 0: "Welcome to ɳClaw", "Step 1 of 7"
//   - OnboardingScreen: "Get Started" button on step 0
//   - OnboardingScreen: Skip button visible on step 0
//   - ModelStatusCard not-installed state: shows "Not installed" label
//   - ModelStatusCard ready state: shows "Ready" and model name
//
// Uses a mocked FlutterSecureStorage channel so no native plugins are needed.

// Hide Flutter's ConnectionState enum to avoid ambiguity with the app's own
// ConnectionState class from connection_provider.dart.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nclaw/screens/onboarding_screen.dart';
import 'package:nclaw/widgets/model_status_card.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Prevent FlutterSecureStorage from throwing MissingPluginException in tests.
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

Widget _wrap(Widget widget) =>
    ProviderScope(child: MaterialApp(home: widget));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(_mockSecureStorage);

  group('OnboardingScreen', () {
    testWidgets('step 0 shows welcome heading and step counter',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await tester.pump(); // first frame

      expect(find.text('Welcome to \u0273Claw'), findsOneWidget);
      expect(find.text('Step 1 of 7'), findsOneWidget);
    });

    testWidgets('step 0 shows "Get Started" action button',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await tester.pump();

      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('skip button is visible on step 0',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await tester.pump();

      // Skip is shown for steps 0–5 (< totalSteps - 1)
      expect(find.text('Skip'), findsOneWidget);
    });
  });

  group('ModelStatusCard', () {
    testWidgets('not-installed state shows "Not installed" and zero counts',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelStatusCard(
              localModel: null,
              localModelStatus: 'none',
              geminiAccounts: 0,
              apiKeyCount: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI Configuration'), findsOneWidget);
      expect(find.text('Not installed'), findsOneWidget);
      expect(find.text('0 accounts'), findsOneWidget);
      expect(find.text('0 keys'), findsOneWidget);
    });

    testWidgets('ready state shows model name and "Ready" label',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelStatusCard(
              localModel: 'phi4-mini',
              localModelStatus: 'ready',
              geminiAccounts: 2,
              apiKeyCount: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('phi4-mini'), findsOneWidget);
      expect(find.text('2 accounts'), findsOneWidget);
      expect(find.text('1 key'), findsOneWidget);
    });
  });
}
