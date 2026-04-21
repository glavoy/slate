import 'package:freezed_annotation/freezed_annotation.dart';
import 'recurrence.dart';

part 'task.freezed.dart';
part 'task.g.dart';

DateTime _dateFromJson(dynamic value) => DateTime.parse(value as String);
String _dateToJson(DateTime dt) => dt.toIso8601String().substring(0, 10);
DateTime? _nullableDateFromJson(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
String? _nullableDateToJson(DateTime? dt) => dt?.toIso8601String();

RecurrenceType _recurrenceFromJson(String value) =>
    RecurrenceTypeX.fromJson(value);
String _recurrenceToJson(RecurrenceType r) => r.toJson();

@freezed
class Task with _$Task {
  const factory Task({
    required String id,
    required String title,
    @JsonKey(
      name: 'due_date',
      fromJson: _dateFromJson,
      toJson: _dateToJson,
    )
    required DateTime dueDate,
    String? notes,
    @JsonKey(name: 'is_done') @Default(false) bool isDone,
    @JsonKey(fromJson: _recurrenceFromJson, toJson: _recurrenceToJson)
    @Default(RecurrenceType.none)
    RecurrenceType recurrence,
    @JsonKey(name: 'due_time') String? dueTime,
    @JsonKey(name: 'series_id') String? seriesId,
    @JsonKey(
      name: 'created_at',
      fromJson: _dateFromJson,
      toJson: _nullableDateToJson,
    )
    required DateTime createdAt,
    @JsonKey(
      name: 'completed_at',
      fromJson: _nullableDateFromJson,
      toJson: _nullableDateToJson,
    )
    DateTime? completedAt,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}
