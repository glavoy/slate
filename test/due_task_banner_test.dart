import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/models/task.dart';
import 'package:slate/providers/task_alert_providers.dart';
import 'package:slate/widgets/due_task_banner.dart';

class _FakeDueAlerts extends DueAlerts {
  _FakeDueAlerts(this.initial);

  final List<Task> initial;
  final dismissed = <String>[];
  final snoozed = <(String, DateTime)>[];
  var dismissAllCalls = 0;

  @override
  List<Task> build() => initial;

  @override
  void dismiss(Task task) {
    dismissed.add(task.id);
    state = [
      for (final t in state)
        if (t.id != task.id) t,
    ];
  }

  @override
  void snoozeUntil(Task task, DateTime until) {
    snoozed.add((task.id, until));
    state = [
      for (final t in state)
        if (t.id != task.id) t,
    ];
  }

  @override
  void dismissAll() {
    dismissAllCalls++;
    state = const [];
  }
}

Task _task(String id, String title, {String? dueTime = '09:00:00'}) => Task(
  id: id,
  title: title,
  dueDate: DateTime(2026, 9, 11),
  dueTime: dueTime,
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  Future<_FakeDueAlerts> pump(WidgetTester tester, List<Task> tasks) async {
    final fake = _FakeDueAlerts(tasks);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dueAlertsProvider.overrideWith(() => fake)],
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [DueTaskBanner()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('renders nothing when no task is due', (tester) async {
    await pump(tester, const []);
    expect(find.byType(Material), findsWidgets);
    expect(find.byIcon(Icons.notifications_active), findsNothing);
  });

  testWidgets('a single alert shows the task with no count chip', (
    tester,
  ) async {
    await pump(tester, [_task('t1', 'Call the dentist')]);

    expect(find.text('Call the dentist'), findsOneWidget);
    expect(find.textContaining('more'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.snooze), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('several alerts collapse to the first with a count', (
    tester,
  ) async {
    await pump(tester, [
      _task('t1', 'Call the dentist'),
      _task('t2', 'Submit timesheet'),
      _task('t3', 'Water the plants'),
    ]);

    expect(find.text('Call the dentist'), findsOneWidget);
    expect(find.text('Submit timesheet'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);
  });

  testWidgets('expanding lists every due task and collapsing returns', (
    tester,
  ) async {
    await pump(tester, [
      _task('t1', 'Call the dentist'),
      _task('t2', 'Submit timesheet'),
      _task('t3', 'Water the plants'),
    ]);

    await tester.tap(find.text('+2 more'));
    await tester.pumpAndSettle();

    expect(find.text('3 tasks due'), findsOneWidget);
    expect(find.text('Call the dentist'), findsOneWidget);
    expect(find.text('Submit timesheet'), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
    expect(find.text('Dismiss all'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pumpAndSettle();
    expect(find.text('Submit timesheet'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);
  });

  testWidgets('dismissing the last alert hides the banner', (tester) async {
    final fake = await pump(tester, [_task('t1', 'Call the dentist')]);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(fake.dismissed, ['t1']);
    expect(find.text('Call the dentist'), findsNothing);
  });

  testWidgets('the expanded view auto-collapses when one alert remains', (
    tester,
  ) async {
    await pump(tester, [
      _task('t1', 'Call the dentist'),
      _task('t2', 'Submit timesheet'),
    ]);

    await tester.tap(find.text('+1 more'));
    await tester.pumpAndSettle();
    expect(find.text('2 tasks due'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(find.text('2 tasks due'), findsNothing);
    expect(find.text('Submit timesheet'), findsOneWidget);
    expect(find.textContaining('more'), findsNothing);
  });

  testWidgets('Dismiss all clears every alert', (tester) async {
    final fake = await pump(tester, [
      _task('t1', 'Call the dentist'),
      _task('t2', 'Submit timesheet'),
    ]);

    await tester.tap(find.text('+1 more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss all'));
    await tester.pumpAndSettle();

    expect(fake.dismissAllCalls, 1);
    expect(find.text('Call the dentist'), findsNothing);
  });

  testWidgets('the snooze menu offers the expected options', (tester) async {
    final fake = await pump(tester, [_task('t1', 'Call the dentist')]);

    await tester.tap(find.byIcon(Icons.snooze));
    await tester.pumpAndSettle();

    expect(find.text('10 minutes'), findsOneWidget);
    expect(find.text('1 hour'), findsOneWidget);
    expect(find.text('3 hours'), findsOneWidget);
    expect(find.text('Tomorrow morning'), findsOneWidget);

    await tester.tap(find.text('1 hour'));
    await tester.pumpAndSettle();

    expect(fake.snoozed.single.$1, 't1');
    expect(find.text('Call the dentist'), findsNothing);
  });

  testWidgets('an all-day task falls back to the configured day start', (
    tester,
  ) async {
    await pump(tester, [_task('t1', 'Tidy the desk', dueTime: null)]);

    // Default day start is 8:00 AM, shown in the 12-hour default format.
    expect(find.textContaining('8:00 AM'), findsOneWidget);
  });
}
