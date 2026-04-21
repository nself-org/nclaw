// Widget tests for FeedbackScreen — exercises render + category dropdown.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/screens/feedback_screen.dart';

void main() {
  testWidgets('FeedbackScreen renders all form fields', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: FeedbackScreen()),
    ));
    await tester.pump();
    expect(find.text('Send Feedback'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Your feedback'), findsOneWidget);
    expect(find.text('Email (optional)'), findsOneWidget);
    expect(find.text('Attach screenshot (optional)'), findsOneWidget);
  });

  testWidgets('Typing in the feedback field does not throw', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: FeedbackScreen()),
    ));
    await tester.pump();
    // Enter text into the Your feedback field (first TextField is category, no wait
    // — category is a Dropdown; so first TextField is message).
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));
    await tester.enterText(textFields.first, 'great app');
    await tester.pump();
  });

  testWidgets('Tapping Send with empty message shows validation snackbar',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: FeedbackScreen()),
    ));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.text('Please enter your feedback'), findsOneWidget);
  });
}
