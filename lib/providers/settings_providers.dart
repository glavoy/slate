import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_providers.g.dart';

const _dateFormatKey = 'date_format';
const _timeFormatKey = 'time_format';

enum DateFormatStyle {
  dayMonthShort('Mon Jan 5'),
  medium('Jan 5, 2026'),
  dmy('5/1/2026'),
  mdy('1/5/2026'),
  iso('2026-01-05');

  final String example;
  const DateFormatStyle(this.example);
}

enum TimeFormatStyle {
  h12('8:00 AM'),
  h24('08:00');

  final String example;
  const TimeFormatStyle(this.example);
}

@Riverpod(keepAlive: true)
class DateFormatNotifier extends _$DateFormatNotifier {
  @override
  DateFormatStyle build() => DateFormatStyle.dayMonthShort;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_dateFormatKey);
    if (stored == null) return;
    state = DateFormatStyle.values.firstWhere(
      (s) => s.name == stored,
      orElse: () => DateFormatStyle.dayMonthShort,
    );
  }

  Future<void> set(DateFormatStyle value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dateFormatKey, value.name);
  }
}

@Riverpod(keepAlive: true)
class TimeFormatNotifier extends _$TimeFormatNotifier {
  @override
  TimeFormatStyle build() => TimeFormatStyle.h12;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_timeFormatKey);
    if (stored == null) return;
    state = TimeFormatStyle.values.firstWhere(
      (s) => s.name == stored,
      orElse: () => TimeFormatStyle.h12,
    );
  }

  Future<void> set(TimeFormatStyle value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timeFormatKey, value.name);
  }
}
