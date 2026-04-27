import 'package:flutter_test/flutter_test.dart';
import 'package:slate/models/recurrence.dart';
import 'package:slate/utils/date_utils.dart';

void main() {
  test('nextOccurrence advances recurring task dates', () {
    final date = DateTime(2026, 4, 27);

    expect(nextOccurrence(date, RecurrenceType.daily), DateTime(2026, 4, 28));
    expect(nextOccurrence(date, RecurrenceType.weekly), DateTime(2026, 5, 4));
    expect(nextOccurrence(date, RecurrenceType.monthly), DateTime(2026, 5, 27));
    expect(nextOccurrence(date, RecurrenceType.yearly), DateTime(2027, 4, 27));
  });
}
