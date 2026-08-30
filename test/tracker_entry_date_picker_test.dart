import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/providers/settings_providers.dart';
import 'package:slate/widgets/tracker_entry_date_picker.dart';

final _today = DateTime(2026, 8, 30);

class _DatePickerHarness extends StatefulWidget {
  final DateTime initialDate;

  const _DatePickerHarness({required this.initialDate});

  @override
  State<_DatePickerHarness> createState() => _DatePickerHarnessState();
}

class _DatePickerHarnessState extends State<_DatePickerHarness> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: TrackerEntryDatePicker(
        selectedDate: _selectedDate,
        today: _today,
        dateStyle: DateFormatStyle.medium,
        onDateChanged: (date) => setState(() => _selectedDate = date),
      ),
    ),
  );
}

void main() {
  testWidgets('moves a tracker entry date to yesterday and back to today', (
    tester,
  ) async {
    await tester.pumpWidget(_DatePickerHarness(initialDate: _today));

    final next = tester.widget<IconButton>(
      find.byKey(const Key('tracker_entry_next_date')),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byKey(const Key('tracker_entry_previous_date')));
    await tester.pump();
    expect(find.text('Yesterday'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tracker_entry_next_date')));
    await tester.pump();
    expect(find.text('Today'), findsNWidgets(2));
  });

  testWidgets('calendar selection and Today reset update the chosen date', (
    tester,
  ) async {
    await tester.pumpWidget(_DatePickerHarness(initialDate: _today));

    await tester.tap(find.byKey(const Key('tracker_entry_calendar_date')));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);

    await tester.tap(find.text('29').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tracker_entry_today_date')));
    await tester.pump();
    expect(find.text('Today'), findsNWidgets(2));
  });

  testWidgets('does not navigate before the earliest allowed date', (
    tester,
  ) async {
    await tester.pumpWidget(_DatePickerHarness(initialDate: DateTime(2000)));

    final previous = tester.widget<IconButton>(
      find.byKey(const Key('tracker_entry_previous_date')),
    );
    expect(previous.onPressed, isNull);
  });
}
