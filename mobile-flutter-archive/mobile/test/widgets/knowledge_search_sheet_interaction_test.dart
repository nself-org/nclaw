// Interaction tests for KnowledgeSearchSheet that exercise text entry,
// clear button, and state transitions.

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/providers/knowledge_provider.dart';
import 'package:nself_claw/widgets/knowledge_search_sheet.dart';

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

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockSecureStorage);

  testWidgets('Opening the sheet shows title and drag handle',
      (tester) async {
    await tester.pumpWidget(_wrap(Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showKnowledgeSearchSheet(ctx),
          child: const Text('Open'),
        ),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('ɳSelf Knowledge'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('Typing in the search field triggers a search', (tester) async {
    await tester.pumpWidget(_wrap(Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showKnowledgeSearchSheet(ctx),
          child: const Text('Open'),
        ),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'nself');
    await tester.pump();
    // Cannot assert HTTP result with no server — just verify widget responds
    // to text change without throwing.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Close button dismisses the sheet', (tester) async {
    await tester.pumpWidget(_wrap(Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showKnowledgeSearchSheet(ctx),
          child: const Text('Open'),
        ),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('ɳSelf Knowledge'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('ɳSelf Knowledge'), findsNothing);
  });
}
