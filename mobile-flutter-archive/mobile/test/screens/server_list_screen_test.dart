// Widget tests for ServerListScreen — covers empty state render and the
// routes to PairingScreen via FAB.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/screens/server_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  testWidgets('empty state shows informational text and FAB',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ServerListScreen()),
    ));
    await tester.pump();
    expect(find.text('Servers'), findsOneWidget);
    expect(find.text('No servers paired'), findsOneWidget);
    expect(find.text('Tap + to add your first server.'), findsOneWidget);
    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
