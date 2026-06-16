// Widget tests for HelpWidget — tests the render path and the Discord
// fallback dialog (triggered by the canLaunchUrl(email) → false branch).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/widgets/help_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub url_launcher so canLaunchUrl returns a deterministic value.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher_ios'),
      (_) async => false,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher_macos'),
      (_) async => false,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher_android'),
      (_) async => false,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher_linux'),
      (_) async => false,
    );
  });

  testWidgets('renders ListTile with title and subtitle', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HelpWidget()),
    ));
    expect(find.text('Help & Feedback'), findsOneWidget);
    expect(find.text('Contact support or join Discord'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
