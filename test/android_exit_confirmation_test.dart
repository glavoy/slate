import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/widgets/android_exit_confirmation.dart';

void main() {
  testWidgets('requires two back presses before exiting', (tester) async {
    var exitCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidExitConfirmation(
          enabled: true,
          onExit: () => exitCalls++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exitCalls, 0);
    expect(find.text('Press back again to exit'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exitCalls, 1);
  });

  testWidgets('does not intercept back when disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AndroidExitConfirmation(
          enabled: false,
          onExit: _ignoreExit,
          child: Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    final popScope = tester.widget<PopScope<Object?>>(
      find.byType(PopScope<Object?>),
    );
    expect(popScope.canPop, isTrue);
  });
}

void _ignoreExit() {}
