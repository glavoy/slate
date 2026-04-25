import 'package:freezed_annotation/freezed_annotation.dart';

part 'tracker_metric.freezed.dart';
part 'tracker_metric.g.dart';

DateTime _dateFromJson(dynamic value) => DateTime.parse(value as String);
String _dateToJson(DateTime dt) => dt.toIso8601String();

@freezed
class TrackerMetric with _$TrackerMetric {
  const factory TrackerMetric({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    required String name,
    String? unit,
    @JsonKey(
      name: 'created_at',
      fromJson: _dateFromJson,
      toJson: _dateToJson,
    )
    required DateTime createdAt,
  }) = _TrackerMetric;

  factory TrackerMetric.fromJson(Map<String, dynamic> json) =>
      _$TrackerMetricFromJson(json);
}
