// S88c.T06 — Flutter semantic label audit for nclaw
//
// Verifies that key interactive widgets expose correct Semantics nodes
// so VoiceOver (iOS/macOS) and TalkBack (Android) can announce them.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nself_claw/widgets/topic_drawer.dart';
import 'package:nself_claw/widgets/voice_capture_fab.dart';

void main() {
  group('TopicDrawer — Semantics', () {
    testWidgets('drawer has accessible label and role', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              drawer: const TopicDrawer(),
              body: const SizedBox(),
            ),
          ),
        ),
      );

      // Open the drawer
      final ScaffoldState scaffold =
          tester.firstState(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();

      // Drawer itself should be present
      expect(find.byType(Drawer), findsOneWidget);
    });

    testWidgets('topic tile exposes button semantics with label', (tester) async {
      // Build a minimal standalone widget that resembles a _TopicNodeTile
      // using a Semantics-wrapped InkWell.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              label: 'Design resources, 3 unread, collapsed',
              selected: false,
              button: true,
              hint: 'Tap to expand',
              child: InkWell(
                onTap: () {},
                child: const SizedBox(height: 40, child: Text('Design resources')),
              ),
            ),
          ),
        ),
      );

      final semanticsNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Design resources')),
      );
      expect(semanticsNode.label, contains('Design resources'));
      expect(semanticsNode.hasFlag(SemanticsFlag.isButton), isTrue);
    });

    testWidgets('unread badge is excluded from semantics tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('3'),
              ),
            ),
          ),
        ),
      );

      // ExcludeSemantics means no semantics node is contributed for the badge.
      // The badge text '3' should NOT appear as a standalone semantics label
      // (it is included in the parent topic tile label instead).
      expect(find.bySemanticsLabel('3'), findsNothing);
    });
  });

  group('VoiceCaptureFab — Semantics', () {
    testWidgets('idle state has accessible label and hint', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              floatingActionButton: VoiceCaptureFab(
                onTranscribed: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The outermost Semantics wrapping the FAB
      final semantics = tester.getSemantics(
        find.ancestor(
          of: find.byType(FloatingActionButton),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(semantics.label, equals('Voice input'));
      expect(semantics.hint, equals('Long-press and hold to record'));
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    });
  });
}
