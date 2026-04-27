import 'package:freezed_annotation/freezed_annotation.dart';

part 'note.freezed.dart';
part 'note.g.dart';

DateTime _dateFromJson(dynamic value) => DateTime.parse(value as String);
String _dateToJson(DateTime dt) => dt.toIso8601String();

DateTime? _dateFromJsonNullable(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
String? _dateToJsonNullable(DateTime? dt) => dt?.toIso8601String();

@freezed
class Note with _$Note {
  const factory Note({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    @Default('') String title,
    @Default('') String content,
    @Default(false) bool pinned,
    @JsonKey(
      name: 'deleted_at',
      fromJson: _dateFromJsonNullable,
      toJson: _dateToJsonNullable,
    )
    @Default(null) DateTime? deletedAt,
    @JsonKey(
      name: 'created_at',
      fromJson: _dateFromJson,
      toJson: _dateToJson,
    )
    required DateTime createdAt,
    @JsonKey(
      name: 'updated_at',
      fromJson: _dateFromJson,
      toJson: _dateToJson,
    )
    required DateTime updatedAt,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}
