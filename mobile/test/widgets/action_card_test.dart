// Widget tests for ActionCard. Exercises all action types, all status chips,
// timestamp formatting, and approve/deny button wiring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/models/claw_action.dart';
import 'package:nself_claw/widgets/action_card.dart';

ClawAction _action({
  ActionType type = ActionType.shell,
  ActionStatus status = ActionStatus.pending,
  Map<String, dynamic> params = const {},
  DateTime? createdAt,
  DateTime? expiresAt,
}) {
  final now = DateTime.now();
  return ClawAction(
    id: 'a1',
    sessionId: 's',
    type: type,
    params: params,
    status: status,
    createdAt: createdAt ?? now.subtract(const Duration(minutes: 2)),
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ActionCard rendering', () {
    testWidgets('shell action shows command and Shell Command label',
        (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          type: ActionType.shell,
          params: const {'command': 'ls -la'},
        ),
      )));
      expect(find.text('Shell Command'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
      expect(find.byIcon(Icons.terminal), findsOneWidget);
    });

    testWidgets('fileOp action shows path', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          type: ActionType.fileOp,
          params: const {'path': '/tmp/foo'},
        ),
      )));
      expect(find.text('File Operation'), findsOneWidget);
      expect(find.text('/tmp/foo'), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    });

    testWidgets('fileOp falls back to operation when path missing',
        (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          type: ActionType.fileOp,
          params: const {'operation': 'delete'},
        ),
      )));
      expect(find.text('delete'), findsOneWidget);
    });

    testWidgets('oauth action shows provider', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          type: ActionType.oauth,
          params: const {'provider': 'google'},
        ),
      )));
      expect(find.text('OAuth Request'), findsOneWidget);
      expect(find.text('google'), findsOneWidget);
      expect(find.byIcon(Icons.key_outlined), findsOneWidget);
    });

    testWidgets('browser action shows URL', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          type: ActionType.browser,
          params: const {'url': 'https://example.com'},
        ),
      )));
      expect(find.text('Open Browser'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_browser), findsOneWidget);
    });

    testWidgets('notification action shows message', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          type: ActionType.notification,
          params: const {'message': 'Hello'},
        ),
      )));
      expect(find.text('Notification'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });

    testWidgets('notification falls back to title when no message',
        (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          type: ActionType.notification,
          params: const {'title': 'The Title'},
        ),
      )));
      expect(find.text('The Title'), findsOneWidget);
    });

    testWidgets('fileOp fallback text when params empty', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(type: ActionType.fileOp, params: const {}),
      )));
      expect(find.text('File operation'), findsOneWidget);
    });

    testWidgets('oauth fallback text when params empty', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(type: ActionType.oauth, params: const {}),
      )));
      expect(find.text('Authentication request'), findsOneWidget);
    });

    testWidgets('shell fallback text when params empty', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(type: ActionType.shell, params: const {}),
      )));
      expect(find.text('Shell command'), findsOneWidget);
    });

    testWidgets('browser fallback text when params empty', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(type: ActionType.browser, params: const {}),
      )));
      expect(find.text('Open URL'), findsOneWidget);
    });

    testWidgets('notification fallback text when params empty', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(type: ActionType.notification, params: const {}),
      )));
      // In this case, "Notification" is BOTH the type label and the fallback,
      // so it appears twice.
      expect(find.text('Notification'), findsNWidgets(2));
    });
  });

  group('Status chip', () {
    testWidgets('pending renders Pending label', (tester) async {
      await tester.pumpWidget(
          _wrap(ActionCard(action: _action(status: ActionStatus.pending))));
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('approved renders Approved', (tester) async {
      await tester.pumpWidget(
          _wrap(ActionCard(action: _action(status: ActionStatus.approved))));
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('executing renders Running and progress bar', (tester) async {
      await tester.pumpWidget(
          _wrap(ActionCard(action: _action(status: ActionStatus.executing))));
      expect(find.text('Running'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('done renders Done', (tester) async {
      await tester
          .pumpWidget(_wrap(ActionCard(action: _action(status: ActionStatus.done))));
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('failed renders Failed', (tester) async {
      await tester.pumpWidget(
          _wrap(ActionCard(action: _action(status: ActionStatus.failed))));
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('expired renders Expired', (tester) async {
      await tester.pumpWidget(
          _wrap(ActionCard(action: _action(status: ActionStatus.expired))));
      expect(find.text('Expired'), findsOneWidget);
    });
  });

  group('Approve/Deny buttons', () {
    testWidgets('pending action with both callbacks shows Approve + Deny',
        (tester) async {
      var approved = false;
      var denied = false;
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(status: ActionStatus.pending),
        onApprove: () => approved = true,
        onDeny: () => denied = true,
      )));
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      expect(approved, true);
      await tester.tap(find.text('Deny'));
      expect(denied, true);
    });

    testWidgets('non-pending action hides buttons', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(status: ActionStatus.done),
        onApprove: () {},
        onDeny: () {},
      )));
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Deny'), findsNothing);
    });

    testWidgets('expired pending action still hides buttons (isPending false)',
        (tester) async {
      final past = DateTime.now().subtract(const Duration(hours: 2));
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
          status: ActionStatus.pending,
          createdAt: past,
          expiresAt: past,
        ),
        onApprove: () {},
        onDeny: () {},
      )));
      expect(find.text('Approve'), findsNothing);
    });
  });

  group('Timestamp formatting', () {
    testWidgets('Just now shows for <1min old', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(createdAt: DateTime.now()),
      )));
      expect(find.text('Just now'), findsOneWidget);
    });

    testWidgets('minutes ago for <60min', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
            createdAt: DateTime.now().subtract(const Duration(minutes: 15))),
      )));
      expect(find.text('15m ago'), findsOneWidget);
    });

    testWidgets('hours ago for <24h', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
            createdAt: DateTime.now().subtract(const Duration(hours: 3))),
      )));
      expect(find.text('3h ago'), findsOneWidget);
    });

    testWidgets('days ago for <7d', (tester) async {
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(
            createdAt: DateTime.now().subtract(const Duration(days: 3))),
      )));
      expect(find.text('3d ago'), findsOneWidget);
    });

    testWidgets('full date shown for >=7d', (tester) async {
      final old = DateTime(2024, 6, 15);
      await tester.pumpWidget(_wrap(ActionCard(action: _action(createdAt: old))));
      expect(find.text('6/15/2024'), findsOneWidget);
    });
  });

  group('onTap', () {
    testWidgets('taps propagate to onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(ActionCard(
        action: _action(),
        onTap: () => tapped = true,
      )));
      await tester.tap(find.byType(InkWell));
      expect(tapped, true);
    });
  });
}
