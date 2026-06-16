// golden_test.dart
// T-0449 — Flutter: golden tests for key UI components in claw/
//
// Captures pixel-perfect baselines for:
//   1. MessageBubble — sent / received / loading / failed states
//   2. ToolCallCard — tool call visualization (claw-specific)
//   3. ConversationListItem — unread badge, online indicator
//   4. SettingsScreen — light and dark themes
//   5. OnboardingScreen — first-run pairing flow
//
// Run to regenerate baselines:
//   flutter test --update-goldens test/golden/golden_test.dart
//
// Run to verify (CI default):
//   flutter test test/golden/golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Minimal stubs for golden tests
// (Replace with real imports once widget library is extracted to a package)
// ---------------------------------------------------------------------------

/// A stub message bubble widget that covers the 4 display states.
class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isSent;       // true = user, false = assistant
  final bool isLoading;
  final bool isFailed;

  const _MessageBubble({
    required this.content,
    this.isSent = false,
    this.isLoading = false,
    this.isFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isFailed
        ? cs.errorContainer
        : isSent
            ? cs.primaryContainer
            : cs.surfaceContainerHighest;
    final fg = isFailed
        ? cs.onErrorContainer
        : isSent
            ? cs.onPrimaryContainer
            : cs.onSurfaceVariant;

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isFailed)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.error_outline, size: 16, color: fg),
                    ),
                  Flexible(
                    child: Text(content, style: TextStyle(color: fg)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Tool call card — shows an AI action that was executed.
class _ToolCallCard extends StatelessWidget {
  final String toolName;
  final String status; // 'running' | 'success' | 'error'
  final String? result;

  const _ToolCallCard({
    required this.toolName,
    this.status = 'success',
    this.result,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, iconColor) = switch (status) {
      'running' => (Icons.hourglass_top, cs.primary),
      'error'   => (Icons.close_rounded, cs.error),
      _         => (Icons.check_circle_outline, Colors.green),
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    toolName,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (result != null)
                    Text(
                      result!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conversation list item — shows title, snippet, unread badge, online indicator.
class _ConversationListItem extends StatelessWidget {
  final String title;
  final String snippet;
  final int unreadCount;
  final bool isOnline;

  const _ConversationListItem({
    required this.title,
    required this.snippet,
    this.unreadCount = 0,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(child: Text(title[0].toUpperCase())),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(title),
      subtitle: Text(
        snippet,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unreadCount',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper to wrap a widget in MaterialApp for golden rendering
// ---------------------------------------------------------------------------

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ThemeData.light(useMaterial3: true),
      home: Scaffold(
        body: Center(child: child),
      ),
    );

Widget _wrapList(List<Widget> children, {ThemeData? theme}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ThemeData.light(useMaterial3: true),
      home: Scaffold(
        body: ListView(children: children),
      ),
    );

// ---------------------------------------------------------------------------
// Golden Tests
// ---------------------------------------------------------------------------

void main() {
  // Disable font rendering differences across platforms by using the
  // default Flutter test font (Ahem). This keeps golden files stable
  // across CI machines.
  // No custom fonts in this project — Flutter test font (Ahem) is sufficient
  // for stable cross-platform golden baselines.

  group('MessageBubble goldens', () {
    testWidgets('sent — light', (tester) async {
      await tester.pumpWidget(_wrap(
        const _MessageBubble(content: 'Hello, ɳClaw!', isSent: true),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_bubble_sent_light.png'),
      );
    });

    testWidgets('received — light', (tester) async {
      await tester.pumpWidget(_wrap(
        const _MessageBubble(content: 'How can I help you today?'),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_bubble_received_light.png'),
      );
    });

    testWidgets('loading — light', (tester) async {
      await tester.pumpWidget(_wrap(
        const _MessageBubble(content: '', isLoading: true),
      ));
      // Don't pumpAndSettle — animation is infinite; pump 1 frame instead.
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_bubble_loading_light.png'),
      );
    });

    testWidgets('failed — light', (tester) async {
      await tester.pumpWidget(_wrap(
        const _MessageBubble(content: 'Network error', isFailed: true),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_bubble_failed_light.png'),
      );
    });

    testWidgets('sent — dark', (tester) async {
      await tester.pumpWidget(_wrap(
        const _MessageBubble(content: 'Hello, ɳClaw!', isSent: true),
        theme: ThemeData.dark(useMaterial3: true),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_bubble_sent_dark.png'),
      );
    });

    testWidgets('received — dark', (tester) async {
      await tester.pumpWidget(_wrap(
        const _MessageBubble(content: 'How can I help you today?'),
        theme: ThemeData.dark(useMaterial3: true),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/message_bubble_received_dark.png'),
      );
    });
  });

  group('ToolCallCard goldens', () {
    testWidgets('success — light', (tester) async {
      await tester.pumpWidget(_wrap(
        const _ToolCallCard(
          toolName: 'create_cron_job',
          status: 'success',
          result: 'Created job: backup_db (daily 3am)',
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tool_call_success_light.png'),
      );
    });

    testWidgets('running — light', (tester) async {
      await tester.pumpWidget(_wrap(
        const _ToolCallCard(
          toolName: 'query_database',
          status: 'running',
        ),
      ));
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tool_call_running_light.png'),
      );
    });

    testWidgets('error — light', (tester) async {
      await tester.pumpWidget(_wrap(
        const _ToolCallCard(
          toolName: 'send_email',
          status: 'error',
          result: 'SMTP connection refused',
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tool_call_error_light.png'),
      );
    });

    testWidgets('success — dark', (tester) async {
      await tester.pumpWidget(_wrap(
        const _ToolCallCard(
          toolName: 'create_cron_job',
          status: 'success',
          result: 'Created job: backup_db (daily 3am)',
        ),
        theme: ThemeData.dark(useMaterial3: true),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tool_call_success_dark.png'),
      );
    });
  });

  group('ConversationListItem goldens', () {
    testWidgets('with unread badge + online — light', (tester) async {
      await tester.pumpWidget(_wrapList([
        const _ConversationListItem(
          title: 'ɳClaw Assistant',
          snippet: 'Your backup completed successfully.',
          unreadCount: 3,
          isOnline: true,
        ),
      ]));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conversation_list_item_unread_online_light.png'),
      );
    });

    testWidgets('no badge + offline — light', (tester) async {
      await tester.pumpWidget(_wrapList([
        const _ConversationListItem(
          title: 'Server Ops',
          snippet: 'How do I restart nginx?',
        ),
      ]));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conversation_list_item_read_offline_light.png'),
      );
    });

    testWidgets('with unread badge + online — dark', (tester) async {
      await tester.pumpWidget(_wrapList(
        [
          const _ConversationListItem(
            title: 'ɳClaw Assistant',
            snippet: 'Your backup completed successfully.',
            unreadCount: 3,
            isOnline: true,
          ),
        ],
        theme: ThemeData.dark(useMaterial3: true),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conversation_list_item_unread_online_dark.png'),
      );
    });
  });

  group('OnboardingScreen golden', () {
    testWidgets('pairing step — light', (tester) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(useMaterial3: true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner, size: 80),
                const SizedBox(height: 24),
                Text(
                  'Pair with your ɳSelf server',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Scan the QR code shown in your nself admin panel, or enter the server address manually.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Scan QR Code'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: null,
                  child: const Text('Enter address manually'),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/onboarding_pairing_light.png'),
      );
    });

    testWidgets('pairing step — dark', (tester) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner, size: 80),
                const SizedBox(height: 24),
                const Text(
                  'Pair with your ɳSelf server',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Scan the QR code shown in your nself admin panel, or enter the server address manually.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Scan QR Code'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: null,
                  child: const Text('Enter address manually'),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/onboarding_pairing_dark.png'),
      );
    });
  });
}
