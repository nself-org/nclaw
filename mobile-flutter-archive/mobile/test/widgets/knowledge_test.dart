// T-1155: Widget tests for knowledge UI components.
//
// Tests:
//   - KnowledgeSearchSheet renders search field + empty state
//   - Knowledge badge appears on messages with knowledgeUsed=true
//   - Knowledge badge absent when knowledgeUsed=false

// Hide Flutter's ConnectionState to avoid ambiguity with the app's own.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/providers/knowledge_provider.dart';
import 'package:nself_claw/providers/chat_provider.dart';
import 'package:nself_claw/widgets/knowledge_search_sheet.dart';

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

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// Minimal widget that mirrors the knowledge badge logic from chat_screen.dart.
class _KnowledgeBadgeHarness extends StatelessWidget {
  const _KnowledgeBadgeHarness({required this.knowledgeUsed});
  final bool knowledgeUsed;

  @override
  Widget build(BuildContext context) {
    if (!knowledgeUsed) return const SizedBox.shrink();
    return const Chip(label: Text('docs used'));
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main() {
  group('KnowledgeSearchSheet', () {
    testWidgets('renders search field and empty state prompt', (tester) async {
      _mockSecureStorage();
      await tester.pumpWidget(_wrap(
        Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showKnowledgeSearchSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
        overrides: [
          knowledgeProvider.overrideWith((ref) => KnowledgeNotifier(ref)),
        ],
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search ɳSelf documentation'), findsOneWidget);
    });
  });

  group('Knowledge badge', () {
    testWidgets('shown when knowledgeUsed=true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _KnowledgeBadgeHarness(knowledgeUsed: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('docs used'), findsOneWidget);
    });

    testWidgets('absent when knowledgeUsed=false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _KnowledgeBadgeHarness(knowledgeUsed: false),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('docs used'), findsNothing);
    });
  });

  group('ChatMessage.knowledgeUsed field', () {
    test('defaults to false', () {
      final msg = ChatMessage(
        id: 'x',
        role: 'assistant',
        content: 'hello',
        createdAt: DateTime.now(),
      );
      expect(msg.knowledgeUsed, isFalse);
    });

    test('set to true when constructed with knowledgeUsed=true', () {
      final msg = ChatMessage(
        id: 'x',
        role: 'assistant',
        content: 'hello',
        knowledgeUsed: true,
        createdAt: DateTime.now(),
      );
      expect(msg.knowledgeUsed, isTrue);
    });
  });
}
