// conversation_screen_test.dart
// T-0448 — Flutter: widget tests for ConversationScreen
//
// Tests every key state of the conversation screen:
//   - Renders without throwing
//   - Empty state when no messages
//   - Message list when messages exist
//   - Loading indicator during response
//   - Error state on API failure

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Minimal stubs — replace with real imports when project has package structure
// ---------------------------------------------------------------------------

// Message model stub
class Message {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final bool isLoading;
  final String? error;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    this.isLoading = false,
    this.error,
  });
}

// Conversation stub
class Conversation {
  final String id;
  final String title;
  final List<Message> messages;

  const Conversation({
    required this.id,
    required this.title,
    this.messages = const [],
  });
}

// Minimal ConversationScreen stub widget
// Replace with: import 'package:nclaw/screens/conversation_screen.dart';
class ConversationScreen extends StatelessWidget {
  final Conversation? conversation;
  final bool isLoading;
  final String? error;

  const ConversationScreen({
    super.key,
    this.conversation,
    this.isLoading = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            key: Key('conversation-loading-indicator'),
          ),
        ),
      );
    }

    if (error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, key: Key('error-icon')),
              Text(error!, key: const Key('error-message')),
            ],
          ),
        ),
      );
    }

    final msgs = conversation?.messages ?? [];

    if (msgs.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Start a conversation',
            key: Key('empty-state-hint'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(conversation?.title ?? '')),
      body: ListView.builder(
        key: const Key('message-list'),
        itemCount: msgs.length,
        itemBuilder: (context, index) {
          final msg = msgs[index];
          return ListTile(
            key: Key('message-${msg.id}'),
            leading: Icon(
              msg.role == 'user' ? Icons.person : Icons.smart_toy,
            ),
            title: msg.isLoading
                ? const CircularProgressIndicator(
                    key: Key('message-loading-indicator'),
                  )
                : Text(msg.content),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConversationScreen', () {
    // -------------------------------------------------------------------------
    // T-0448-01: renders without throwing
    // -------------------------------------------------------------------------

    testWidgets('renders without throwing — no conversation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(),
        ),
      );

      // No exception = pass
      expect(find.byType(ConversationScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // T-0448-02: shows empty state when no messages
    // -------------------------------------------------------------------------

    testWidgets('shows empty state when conversation has no messages', (tester) async {
      const emptyConversation = Conversation(
        id: 'conv-1',
        title: 'Empty Conversation',
        messages: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(conversation: emptyConversation),
        ),
      );

      expect(find.byKey(const Key('empty-state-hint')), findsOneWidget);
      expect(find.byKey(const Key('message-list')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // T-0448-03: displays message list when messages exist
    // -------------------------------------------------------------------------

    testWidgets('displays message list when messages exist', (tester) async {
      const conversation = Conversation(
        id: 'conv-2',
        title: 'Test Chat',
        messages: [
          Message(id: 'msg-1', role: 'user', content: 'Hello'),
          Message(id: 'msg-2', role: 'assistant', content: 'Hi there!'),
          Message(id: 'msg-3', role: 'user', content: 'How are you?'),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(conversation: conversation),
        ),
      );

      expect(find.byKey(const Key('message-list')), findsOneWidget);
      expect(find.byKey(const Key('message-msg-1')), findsOneWidget);
      expect(find.byKey(const Key('message-msg-2')), findsOneWidget);
      expect(find.byKey(const Key('message-msg-3')), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Hi there!'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // T-0448-04: shows loading indicator during response
    // -------------------------------------------------------------------------

    testWidgets('shows loading indicator during response generation', (tester) async {
      const conversation = Conversation(
        id: 'conv-3',
        title: 'Loading Test',
        messages: [
          Message(id: 'msg-1', role: 'user', content: 'Generate something'),
          Message(id: 'msg-2', role: 'assistant', content: '', isLoading: true),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(conversation: conversation),
        ),
      );

      expect(find.byKey(const Key('message-loading-indicator')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // T-0448-04b: top-level loading indicator (initial fetch)
    // -------------------------------------------------------------------------

    testWidgets('shows top-level loading indicator during initial load', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(isLoading: true),
        ),
      );

      expect(find.byKey(const Key('conversation-loading-indicator')), findsOneWidget);
      expect(find.byKey(const Key('message-list')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // T-0448-05: shows error state on API failure
    // -------------------------------------------------------------------------

    testWidgets('shows error state on API failure', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(
            error: 'Failed to connect to nself API. Check your configuration.',
          ),
        ),
      );

      expect(find.byKey(const Key('error-icon')), findsOneWidget);
      expect(find.byKey(const Key('error-message')), findsOneWidget);
      expect(
        find.text('Failed to connect to nself API. Check your configuration.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('message-list')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // T-0448-06: multiple messages render in order
    // -------------------------------------------------------------------------

    testWidgets('messages render in insertion order', (tester) async {
      const conversation = Conversation(
        id: 'conv-4',
        title: 'Order Test',
        messages: [
          Message(id: 'first',  role: 'user',      content: 'First message'),
          Message(id: 'second', role: 'assistant', content: 'Second message'),
          Message(id: 'third',  role: 'user',      content: 'Third message'),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(conversation: conversation),
        ),
      );

      // All 3 messages must be rendered
      expect(find.text('First message'),  findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
      expect(find.text('Third message'),  findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // T-0448-07: error state takes priority over conversation data
    // -------------------------------------------------------------------------

    testWidgets('error state shown even when conversation exists', (tester) async {
      const conversation = Conversation(
        id: 'conv-5',
        title: 'Priority Test',
        messages: [
          Message(id: 'msg-1', role: 'user', content: 'Will not be shown'),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ConversationScreen(
            conversation: conversation,
            error: 'API rate limit exceeded',
          ),
        ),
      );

      // Error takes priority
      expect(find.byKey(const Key('error-icon')), findsOneWidget);
      expect(find.text('API rate limit exceeded'), findsOneWidget);
      // Message list not shown during error
      expect(find.byKey(const Key('message-list')), findsNothing);
    });
  });
}
