// Widget test for GreetingHeader — exercises ConsumerWidget render path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/widgets/greeting_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  testWidgets('renders a greeting when displayName is empty', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: GreetingHeader()),
      ),
    ));
    await tester.pump();
    // Greeting always ends in a period; pick any of the 5 greetings.
    final greetings = [
      'Working late.',
      'Good morning.',
      'Good afternoon.',
      'Good evening.',
      'Up late.',
    ];
    final found = greetings.any((g) => find.text(g).evaluate().isNotEmpty);
    expect(found, true, reason: 'expected one of: $greetings');
  });

  testWidgets('renders with subtitle', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: GreetingHeader(subtitle: 'How can I help today?'),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('How can I help today?'), findsOneWidget);
  });
}
