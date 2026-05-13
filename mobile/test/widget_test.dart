import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nself_claw/main.dart';

void main() {
  testWidgets('NClawApp renders pairing screen when no server configured',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: NClawApp()),
    );
    await tester.pumpAndSettle();

    // Should show the pairing screen heading and the default Scan QR tab.
    expect(find.text('Connect to your server'), findsOneWidget);
    expect(find.text('Scan QR'), findsWidgets); // tab label
  });
}
