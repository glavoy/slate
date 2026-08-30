import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/screens/tracker_metric_screen.dart';
import 'package:slate/utils/tracker_chart_utils.dart';

Future<void> _pumpControls(
  WidgetTester tester, {
  required double width,
  required ValueChanged<TrackerChartType> onChartTypeChanged,
  required ValueChanged<TrackerChartPeriod> onPeriodChanged,
  required VoidCallback onPickStart,
  required VoidCallback onPickEnd,
  bool expanded = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: TrackerChartControls(
              chartType: TrackerChartType.line,
              period: TrackerChartPeriod.daily,
              startDate: DateTime(2026, 8, 1),
              endDate: DateTime(2026, 8, 30),
              formatDate: (date) => '${date.month}/${date.day}',
              onChartTypeChanged: onChartTypeChanged,
              onPeriodChanged: onPeriodChanged,
              onPickStart: onPickStart,
              onPickEnd: onPickEnd,
              expanded: expanded,
              onToggleExpanded: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('phone layout stacks all chart controls without a scroll strip', (
    tester,
  ) async {
    TrackerChartType? selectedType;
    TrackerChartPeriod? selectedPeriod;
    var startPicks = 0;
    var endPicks = 0;

    await _pumpControls(
      tester,
      width: 390,
      onChartTypeChanged: (value) => selectedType = value,
      onPeriodChanged: (value) => selectedPeriod = value,
      onPickStart: () => startPicks++,
      onPickEnd: () => endPicks++,
    );

    expect(
      find.byKey(const Key('tracker_chart_mobile_controls')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tracker_chart_desktop_controls')),
      findsNothing,
    );
    expect(find.text('Line'), findsOneWidget);
    expect(find.text('Bar'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.byKey(const Key('tracker_chart_start_date')), findsOneWidget);
    expect(find.byKey(const Key('tracker_chart_end_date')), findsOneWidget);
    expect(find.text('Aug 1 2026'), findsOneWidget);
    expect(find.text('Aug 30 2026'), findsOneWidget);

    final chartTypeSelector = tester.widget<SegmentedButton<TrackerChartType>>(
      find.byType(SegmentedButton<TrackerChartType>),
    );
    final periodSelector = tester.widget<SegmentedButton<TrackerChartPeriod>>(
      find.byType(SegmentedButton<TrackerChartPeriod>),
    );
    expect(chartTypeSelector.showSelectedIcon, isFalse);
    expect(periodSelector.showSelectedIcon, isFalse);

    await tester.tap(find.text('Bar'));
    await tester.pump();
    expect(selectedType, TrackerChartType.bar);

    await tester.tap(find.text('Weekly'));
    await tester.pump();
    expect(selectedPeriod, TrackerChartPeriod.weekly);

    await tester.tap(find.byKey(const Key('tracker_chart_start_date')));
    await tester.tap(find.byKey(const Key('tracker_chart_end_date')));
    expect(startPicks, 1);
    expect(endPicks, 1);
  });

  testWidgets('wide layout retains the desktop control strip', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpControls(
      tester,
      width: 1000,
      onChartTypeChanged: (_) {},
      onPeriodChanged: (_) {},
      onPickStart: () {},
      onPickEnd: () {},
    );

    expect(
      find.byKey(const Key('tracker_chart_mobile_controls')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('tracker_chart_desktop_controls')),
      findsOneWidget,
    );
  });

  testWidgets('intermediate widths retain the stacked controls', (
    tester,
  ) async {
    await _pumpControls(
      tester,
      width: 700,
      onChartTypeChanged: (_) {},
      onPeriodChanged: (_) {},
      onPickStart: () {},
      onPickEnd: () {},
    );

    expect(
      find.byKey(const Key('tracker_chart_mobile_controls')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tracker_chart_end_date')), findsOneWidget);
  });

  testWidgets('collapsed controls only show the expand button', (tester) async {
    await _pumpControls(
      tester,
      width: 390,
      expanded: false,
      onChartTypeChanged: (_) {},
      onPeriodChanged: (_) {},
      onPickStart: () {},
      onPickEnd: () {},
    );

    expect(
      find.byKey(const Key('tracker_chart_collapsed_toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tracker_chart_mobile_controls')),
      findsNothing,
    );
    expect(find.byKey(const Key('tracker_chart_start_date')), findsNothing);
    expect(find.byKey(const Key('tracker_chart_end_date')), findsNothing);
  });
}
