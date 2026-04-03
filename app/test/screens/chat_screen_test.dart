// T-1070: Widget tests for ChatScreen.
//
// Tests:
//   - Empty state renders correctly (no messages, not streaming)
//   - Typing indicator (CircularProgressIndicator) shown when streaming
//   - AppBar shows the active session title
//
// Uses ProviderScope overrides and a mocked FlutterSecureStorage channel so
// no network calls or native plugins are needed.

// Hide Flutter's ConnectionState enum to avoid ambiguity with the app's own
// ConnectionState class from connection_provider.dart.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nclaw/providers/chat_provider.dart';
import 'package:nclaw/screens/chat_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Prevent FlutterSecureStorage from throwing MissingPluginException in tests.
/// Returns an empty map for read operations, no-ops for writes.
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

/// A [ChatNotifier] that starts with a preset [ChatState].
class _FakeChatNotifier extends ChatNotifier {
  _FakeChatNotifier(ChatState initial) {
    state = initial;
  }
}

/// Wrap [widget] in a [ProviderScope] that overrides the given providers.
/// The connectionProvider initialises normally with a mocked storage channel.
Widget _wrap(Widget widget, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: widget),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(_mockSecureStorage);

  group('ChatScreen', () {
    testWidgets('empty state shows prompt text when no messages',
        (WidgetTester tester) async {
      final emptyState = ChatState(
        sessions: [
          ChatSession(
            id: 'test-session',
            title: 'New Chat',
            createdAt: DateTime(2026),
          ),
        ],
        activeSessionId: 'test-session',
        isStreaming: false,
      );

      await tester.pumpWidget(
        _wrap(
          const ChatScreen(),
          overrides: [
            chatProvider.overrideWith((_) => _FakeChatNotifier(emptyState)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Empty-state prompt text
      expect(find.text('Ask \u0273Claw anything'), findsOneWidget);

      // No spinner in non-streaming empty state
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows CircularProgressIndicator when isStreaming=true',
        (WidgetTester tester) async {
      final streamingState = ChatState(
        sessions: [
          ChatSession(
            id: 'streaming-session',
            title: 'New Chat',
            createdAt: DateTime(2026),
          ),
        ],
        activeSessionId: 'streaming-session',
        isStreaming: true,
        streamingContent: '',
      );

      await tester.pumpWidget(
        _wrap(
          const ChatScreen(),
          overrides: [
            chatProvider
                .overrideWith((_) => _FakeChatNotifier(streamingState)),
          ],
        ),
      );
      // Use pump instead of pumpAndSettle — CircularProgressIndicator is an
      // infinite animation and pumpAndSettle would time out.
      await tester.pump();

      // Spinner shown while streaming (both _EmptyChat and _InputBar show one).
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));

      // Prompt text hidden while streaming
      expect(find.text('Ask \u0273Claw anything'), findsNothing);
    });

    testWidgets('AppBar displays the active session title',
        (WidgetTester tester) async {
      final namedState = ChatState(
        sessions: [
          ChatSession(
            id: 'named-session',
            title: 'Test Session',
            createdAt: DateTime(2026),
          ),
        ],
        activeSessionId: 'named-session',
        isStreaming: false,
      );

      await tester.pumpWidget(
        _wrap(
          const ChatScreen(),
          overrides: [
            chatProvider.overrideWith((_) => _FakeChatNotifier(namedState)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Session'), findsOneWidget);
    });
  });
}
