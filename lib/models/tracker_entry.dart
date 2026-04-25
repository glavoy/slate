import 'package:freezed_annotation/freezed_annotation.dart';

part 'tracker_entry.freezed.dart';
part 'tracker_entry.g.dart';

DateTime _dateFromJson(dynamic value) => DateTime.parse(value as String);
String _dateToJson(DateTime dt) => dt.toIso8601String();
double _valueFromJson(dynamic value) => (value as num).toDouble();

@freezed
class TrackerEntry with _$TrackerEntry {
  const factory TrackerEntry({
    required String id,
    @JsonKey(name: 'metric_id') required String metricId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(fromJson: _valueFromJson) required double value,
    @JsonKey(
      name: 'recorded_at',
      fromJson: _dateFromJson,
      toJson: _dateToJson,
    )
    required DateTime recordedAt,
    String? note,
  }) = _TrackerEntry;

  factory TrackerEntry.fromJson(Map<String, dynamic> json) =>
      _$TrackerEntryFromJson(json);
}
