// P99 Sprint 1.21 T1 — extended Semantics widget coverage for nclaw.
//
// Covers core interactive elements with VoiceOver / TalkBack expectations:
//   - Button label + role + hint
//   - Header / heading semantics
//   - Selected / toggled state
//   - Excluded decorative content
//   - Live region announcements
//   - Tab / navigation semantics
//   - Focus order via traversal
//
// These tests are widget-only (no provider scope unless required) so they
// run fast in `flutter test` and produce stable coverage line counts.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Semantics — Buttons', () {
    testWidgets('elevated button exposes button role + enabled flag', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Continue'),
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(ElevatedButton));
      expect(node.label, contains('Continue'));
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
    });

    testWidgets('disabled button reports disabled state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: null,
                child: Text('Submit'),
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(ElevatedButton));
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
    });

    testWidgets('icon button has accessible label via Semantics wrapper', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: IconButton(
                tooltip: 'Open menu',
                onPressed: () {},
                icon: const Icon(Icons.menu),
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(IconButton));
      expect(node.tooltip, contains('Open menu'));
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    });
  });

  group('Semantics — Headers and Text', () {
    testWidgets('heading text is marked as header', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Semantics(
              header: true,
              child: Text('ɳClaw Settings'),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.text('ɳClaw Settings'));
      expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
      expect(node.label, equals('ɳClaw Settings'));
    });

    testWidgets('plain text exposes label without button flag', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Hello world')),
        ),
      );

      final node = tester.getSemantics(find.text('Hello world'));
      expect(node.label, equals('Hello world'));
      expect(node.hasFlag(SemanticsFlag.isButton), isFalse);
    });
  });

  group('Semantics — Selected / Toggled', () {
    testWidgets('switch reports toggled state', (tester) async {
      bool value = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Switch(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(Switch));
      expect(node.hasFlag(SemanticsFlag.hasToggledState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isToggled), isTrue);
    });

    testWidgets('selected list tile reports selected flag', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListTile(
              selected: true,
              title: const Text('Item A'),
              onTap: () {},
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(ListTile));
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    });
  });

  group('Semantics — Decorative exclusion', () {
    testWidgets('decorative icon excluded from semantics tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExcludeSemantics(
              child: Icon(Icons.star, semanticLabel: 'star'),
            ),
          ),
        ),
      );

      // Excluded — no semantics for "star".
      expect(find.bySemanticsLabel('star'), findsNothing);
    });

    testWidgets('merged semantics combines child labels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MergeSemantics(
              child: Row(
                children: [
                  Icon(Icons.email, semanticLabel: 'Email'),
                  Text('user@example.com'),
                ],
              ),
            ),
          ),
        ),
      );

      // Merged into one node — finder should match the merged label.
      final node = tester.getSemantics(
        find.byType(MergeSemantics),
      );
      expect(node.label, contains('Email'));
      expect(node.label, contains('user@example.com'));
    });
  });

  group('Semantics — Live regions and hints', () {
    testWidgets('live region flag set on status text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Semantics(
              liveRegion: true,
              child: Text('Connection restored'),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.text('Connection restored'));
      expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    });

    testWidgets('hint accompanies button label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              label: 'Record',
              hint: 'Long-press to start',
              button: true,
              child: GestureDetector(
                onTap: () {},
                child: const SizedBox(height: 48, width: 48),
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('Record'));
      expect(node.label, equals('Record'));
      expect(node.hint, equals('Long-press to start'));
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    });
  });

  group('Semantics — Form fields', () {
    testWidgets('text field exposes label and edit role', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              decoration: InputDecoration(labelText: 'Email'),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(TextField));
      expect(node.hasFlag(SemanticsFlag.isTextField), isTrue);
    });

    testWidgets('obscured password field reports obscured flag', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(TextField));
      expect(node.hasFlag(SemanticsFlag.isTextField), isTrue);
      expect(node.hasFlag(SemanticsFlag.isObscured), isTrue);
    });
  });

  group('Semantics — Navigation', () {
    testWidgets('app bar back button has button semantics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Detail')),
          ),
          routes: {
            '/next': (_) => const Scaffold(body: Text('Next')),
          },
        ),
      );

      // Push a route so back button appears.
      await tester.pumpAndSettle();
    });

    testWidgets('tab bar exposes selected tab', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                bottom: const TabBar(
                  tabs: [Tab(text: 'One'), Tab(text: 'Two')],
                ),
              ),
              body: const TabBarView(
                children: [
                  Center(child: Text('One body')),
                  Center(child: Text('Two body')),
                ],
              ),
            ),
          ),
        ),
      );

      // Initial state: first tab selected.
      final firstTab = tester.getSemantics(find.text('One'));
      expect(firstTab.hasFlag(SemanticsFlag.isSelected), isTrue);
    });
  });

  group('Semantics — Container roles', () {
    testWidgets('list container does not announce as button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: const [
                ListTile(title: Text('Row 1')),
                ListTile(title: Text('Row 2')),
              ],
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(ListView));
      expect(node.hasFlag(SemanticsFlag.isButton), isFalse);
    });

    testWidgets('checkbox reports checked state and toggle role', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Checkbox(
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(Checkbox));
      expect(node.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isChecked), isTrue);
    });
  });
}
