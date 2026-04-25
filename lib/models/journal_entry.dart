import 'package:freezed_annotation/freezed_annotation.dart';

part 'journal_entry.freezed.dart';
part 'journal_entry.g.dart';

DateTime _dateFromJson(dynamic value) => DateTime.parse(value as String);
String _dateToJson(DateTime dt) => dt.toIso8601String();
String _dateOnlyToJson(DateTime dt) => dt.toIso8601String().substring(0, 10);

@freezed
class JournalEntry with _$JournalEntry {
  const factory JournalEntry({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(
      name: 'entry_date',
      fromJson: _dateFromJson,
      toJson: _dateOnlyToJson,
    )
    required DateTime entryDate,
    @Default('') String content,
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
  }) = _JournalEntry;

  factory JournalEntry.fromJson(Map<String, dynamic> json) =>
      _$JournalEntryFromJson(json);
}
