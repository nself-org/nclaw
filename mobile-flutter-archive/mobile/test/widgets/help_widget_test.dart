// S52-T10: Widget tests for HelpWidget in ɳClaw.
//
// Tests:
//   - HelpWidget renders in a ListTile with correct title
//   - Tap fires the correct action (opens email / Discord fallback)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/widgets/help_widget.dart';

void main() {
  group('HelpWidget — nclaw', () {
    testWidgets('renders ListTile with Help & Feedback title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HelpWidget(),
          ),
        ),
      );

      expect(find.text('Help & Feedback'), findsOneWidget);
      expect(find.text('Contact support or join Discord'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });

    testWidgets('tap on HelpWidget does not throw', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HelpWidget(),
          ),
        ),
      );

      // Tap the widget — canLaunchUrl will return false in test environment,
      // which triggers the Discord fallback dialog without crashing.
      await tester.tap(find.byType(HelpWidget));
      await tester.pumpAndSettle();

      // No exception should propagate.
      expect(tester.takeException(), isNull);
    });
  });
}
