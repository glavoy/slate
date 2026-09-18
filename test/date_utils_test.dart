import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/utils/date_utils.dart';

void main() {
  group('nextHourDefaultDueTime', () {
    test('rounds up to the next full hour', () {
      final result = nextHourDefaultDueTime(DateTime(2026, 9, 18, 9, 20));
      expect(result, const TimeOfDay(hour: 10, minute: 0));
    });

    test('advances even when already on the hour', () {
      final result = nextHourDefaultDueTime(DateTime(2026, 9, 18, 9, 0));
      expect(result, const TimeOfDay(hour: 10, minute: 0));
    });

    test('wraps past midnight', () {
      final result = nextHourDefaultDueTime(DateTime(2026, 9, 18, 23, 45));
      expect(result, const TimeOfDay(hour: 0, minute: 0));
    });
  });
}
