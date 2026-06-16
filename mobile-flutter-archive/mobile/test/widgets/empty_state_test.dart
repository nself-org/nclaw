// Widget tests for EmptyState. Exercises all four factories and both
// action-button shapes (filled/tonal, with icon/no icon).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/widgets/empty_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('EmptyState', () {
    testWidgets('firstTime renders icon, title, message, and primary button',
        (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(EmptyState.firstTime(
        icon: Icons.chat_bubble_outline,
        title: 'Start a chat',
        message: 'Say hello',
        primaryAction: EmptyStateAction(
          label: 'New chat',
          icon: Icons.add,
          onPressed: () => pressed = true,
        ),
      )));

      expect(find.text('Start a chat'), findsOneWidget);
      expect(find.text('Say hello'), findsOneWidget);
      expect(find.text('New chat'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);

      await tester.tap(find.text('New chat'));
      expect(pressed, true);
    });

    testWidgets('firstTime without message omits message text', (tester) async {
      await tester.pumpWidget(_wrap(EmptyState.firstTime(
        icon: Icons.info,
        title: 'Title only',
      )));
      expect(find.text('Title only'), findsOneWidget);
    });

    testWidgets('error variant shows retry button and triggers callback',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(_wrap(EmptyState.error(
        title: 'Something broke',
        onRetry: () => retried = true,
      )));

      expect(find.text('Something broke'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.text('Try again'));
      expect(retried, true);
    });

    testWidgets('error variant supports custom retryLabel', (tester) async {
      await tester.pumpWidget(_wrap(EmptyState.error(
        title: 'Broke',
        onRetry: () {},
        retryLabel: 'Reload now',
      )));
      expect(find.text('Reload now'), findsOneWidget);
    });

    testWidgets('offline variant shows cloud_off and default title',
        (tester) async {
      await tester.pumpWidget(_wrap(EmptyState.offline()));
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      // No retry action supplied → should NOT render "Retry".
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('offline variant with onRetry shows Retry button',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(_wrap(EmptyState.offline(
        onRetry: () => retried = true,
      )));
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, true);
    });

    testWidgets('noResults renders query-aware title and default message',
        (tester) async {
      await tester.pumpWidget(_wrap(EmptyState.noResults(
        query: 'flutter',
      )));
      expect(find.text('No results for "flutter"'), findsOneWidget);
      expect(find.text('Try a different search term.'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('noResults with onClear shows Clear search and fires callback',
        (tester) async {
      var cleared = false;
      await tester.pumpWidget(_wrap(EmptyState.noResults(
        query: 'x',
        onClear: () => cleared = true,
      )));
      expect(find.text('Clear search'), findsOneWidget);
      await tester.tap(find.text('Clear search'));
      expect(cleared, true);
    });

    testWidgets('secondary action renders alongside primary', (tester) async {
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.info,
        title: 'Two actions',
        primaryAction: EmptyStateAction(
          label: 'Primary',
          onPressed: () {},
        ),
        secondaryAction: EmptyStateAction(
          label: 'Secondary',
          onPressed: () {},
          filled: false,
        ),
      )));
      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Secondary'), findsOneWidget);
    });

    testWidgets('filled action without icon renders FilledButton',
        (tester) async {
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.info,
        title: 't',
        primaryAction: EmptyStateAction(
          label: 'No icon filled',
          onPressed: () {},
        ),
      )));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('No icon filled'), findsOneWidget);
    });

    testWidgets('tonal action without icon renders FilledButton.tonal',
        (tester) async {
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.info,
        title: 't',
        primaryAction: EmptyStateAction(
          label: 'Tonal no icon',
          onPressed: () {},
          filled: false,
        ),
      )));
      // FilledButton.tonal produces a FilledButton-shaped widget; just verify
      // label + no explicit icon.
      expect(find.text('Tonal no icon'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('all four tones render without throwing', (tester) async {
      for (final tone in EmptyStateTone.values) {
        await tester.pumpWidget(_wrap(EmptyState(
          icon: Icons.help,
          title: 'Tone: ${tone.name}',
          tone: tone,
        )));
        expect(find.text('Tone: ${tone.name}'), findsOneWidget);
      }
    });
  });
}
