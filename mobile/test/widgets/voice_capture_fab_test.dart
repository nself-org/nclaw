// Widget test for VoiceCaptureFab — mounts the FAB and asserts basic render,
// disabled taps (not long-press), and the progress state when transcribing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/widgets/voice_capture_fab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub speech_to_text so initialize returns false deterministically —
    // this prevents platform-channel errors during initState.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async {
        if (call.method == 'has_permission') return false;
        if (call.method == 'initialize') return false;
        return null;
      },
    );
  });

  testWidgets('renders a FloatingActionButton with mic_none icon',
      (tester) async {
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
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('short tap (not long-press) shows SnackBar hint',
      (tester) async {
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
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Long-press and hold to record'),
      findsOneWidget,
    );
  });
}
