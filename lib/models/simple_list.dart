import 'package:freezed_annotation/freezed_annotation.dart';

part 'simple_list.freezed.dart';
part 'simple_list.g.dart';

DateTime _dateFromJson(dynamic value) => DateTime.parse(value as String);
String _dateToJson(DateTime dt) => dt.toIso8601String();

@freezed
class SimpleList with _$SimpleList {
  const factory SimpleList({
    @JsonKey(name: 'user_id') required String userId,
    @Default('') String content,
    @JsonKey(
      name: 'updated_at',
      fromJson: _dateFromJson,
      toJson: _dateToJson,
    )
    required DateTime updatedAt,
  }) = _SimpleList;

  factory SimpleList.fromJson(Map<String, dynamic> json) =>
      _$SimpleListFromJson(json);
}
