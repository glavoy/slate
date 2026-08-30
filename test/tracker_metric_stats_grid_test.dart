import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/screens/tracker_screen.dart';

Future<void> _pumpGrid(WidgetTester tester, double width) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: TrackerMetricStatsGrid(
              children: [
                for (var i = 0; i < 4; i++)
                  SizedBox(
                    key: Key('stat-$i'),
                    height: 24,
                    child: Text('Stat $i'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('uses two compact columns at phone widths', (tester) async {
    await _pumpGrid(tester, 320);

    final first = tester.getTopLeft(find.byKey(const Key('stat-0')));
    final second = tester.getTopLeft(find.byKey(const Key('stat-1')));
    final third = tester.getTopLeft(find.byKey(const Key('stat-2')));

    expect(second.dx, greaterThan(first.dx));
    expect(third.dy, greaterThan(first.dy));
  });

  testWidgets('uses four columns when enough width is available', (
    tester,
  ) async {
    await _pumpGrid(tester, 800);

    final first = tester.getTopLeft(find.byKey(const Key('stat-0')));
    final fourth = tester.getTopLeft(find.byKey(const Key('stat-3')));

    expect(fourth.dx, greaterThan(first.dx));
    expect(fourth.dy, first.dy);
  });
}
