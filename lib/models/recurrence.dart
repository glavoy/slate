enum RecurrenceType { none, daily, weekly, monthly, yearly }

extension RecurrenceTypeX on RecurrenceType {
  String get label => switch (this) {
        RecurrenceType.none => 'None',
        RecurrenceType.daily => 'Daily',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.monthly => 'Monthly',
        RecurrenceType.yearly => 'Yearly',
      };

  String toJson() => name;

  static RecurrenceType fromJson(String value) =>
      RecurrenceType.values.firstWhere((e) => e.name == value);
}
