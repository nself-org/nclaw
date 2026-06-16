// Tests for timeOfDayGreeting — pure function. Skip the ConsumerWidget itself
// since it depends on secure storage load through settingsProvider.

import 'package:flutter_test/flutter_test.dart';

import 'package:nself_claw/widgets/greeting_header.dart';

void main() {
  group('timeOfDayGreeting', () {
    test('"Working late" before 5 AM', () {
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 0, 30)), 'Working late');
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 4, 59)), 'Working late');
    });

    test('"Good morning" 5-11am', () {
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 5, 0)), 'Good morning');
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 9, 0)), 'Good morning');
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 11, 59)), 'Good morning');
    });

    test('"Good afternoon" 12-16', () {
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 12, 0)), 'Good afternoon');
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 16, 59)), 'Good afternoon');
    });

    test('"Good evening" 17-21', () {
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 17, 0)), 'Good evening');
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 21, 59)), 'Good evening');
    });

    test('"Up late" 22+', () {
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 22, 0)), 'Up late');
      expect(timeOfDayGreeting(DateTime(2026, 1, 1, 23, 59)), 'Up late');
    });
  });
}
