import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/models/note.dart';
import 'package:slate/providers/note_providers.dart';
import 'package:slate/widgets/note_editor_pane.dart';

void main() {
  testWidgets('does not replace focused editor text on sync refresh', (
    tester,
  ) async {
    final initial = _note(
      title: 'Initial title',
      content: 'Initial body',
      updatedAt: DateTime.utc(2026, 5, 10, 12),
    );
    late _FakeNoteList fakeNotes;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteListProvider.overrideWith(() {
            fakeNotes = _FakeNoteList(initial);
            return fakeNotes;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NoteEditorPane(noteId: 'note-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const localText = 'Local title\nLocal body';
    final fieldFinder = find.byType(TextField);
    await tester.tap(fieldFinder);
    await tester.enterText(fieldFinder, localText);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();

    var textField = tester.widget<TextField>(fieldFinder);
    expect(textField.controller!.text, localText);
    expect(textField.focusNode!.hasFocus, isTrue);
    expect(textField.controller!.selection.baseOffset, localText.length);

    fakeNotes.replace(
      _note(
        title: 'Remote title',
        content: 'Remote body',
        updatedAt: DateTime.utc(2026, 5, 10, 12, 1),
      ),
    );
    await tester.pump();

    textField = tester.widget<TextField>(fieldFinder);
    expect(textField.controller!.text, localText);
    expect(textField.controller!.selection.baseOffset, localText.length);
  });

  testWidgets('controller toggles checkbox marker on body lines', (
    tester,
  ) async {
    final editorController = NoteEditorController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteListProvider.overrideWith(
            () => _FakeNoteList(
              _note(
                title: 'Title',
                content: 'Task',
                updatedAt: DateTime.utc(2026, 5, 10, 12),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditorPane(
              noteId: 'note-1',
              controller: editorController,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const initialText = 'Title\nTask';
    final fieldFinder = find.byType(TextField);
    await tester.tap(fieldFinder);
    await tester.enterText(fieldFinder, initialText);

    final textField = tester.widget<TextField>(fieldFinder);
    textField.controller!.selection = const TextSelection.collapsed(
      offset: initialText.length,
    );
    editorController.toggleCheckbox();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n☐ Task');
    expect(textField.controller!.selection.baseOffset, 'Title\n☐ Task'.length);
  });

  testWidgets('hyphen list continues after pressing enter', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteListProvider.overrideWith(
            () => _FakeNoteList(
              _note(
                title: 'Title',
                content: '',
                updatedAt: DateTime.utc(2026, 5, 10, 12),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NoteEditorPane(noteId: 'note-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const textBeforeEnter = 'Title\n- item';
    const textAfterEnter = '$textBeforeEnter\n';
    final fieldFinder = find.byType(TextField);
    await tester.tap(fieldFinder);
    await tester.enterText(fieldFinder, textBeforeEnter);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: textAfterEnter,
        selection: TextSelection.collapsed(offset: textAfterEnter.length),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(fieldFinder);
    expect(textField.controller!.text, 'Title\n- item\n- ');
    expect(
      textField.controller!.selection.baseOffset,
      'Title\n- item\n- '.length,
    );
  });
}

Note _note({
  required String title,
  required String content,
  required DateTime updatedAt,
}) {
  return Note(
    id: 'note-1',
    userId: 'user-1',
    title: title,
    content: content,
    createdAt: DateTime.utc(2026, 5, 10, 11),
    updatedAt: updatedAt,
    syncStatus: 'synced',
    lastSyncedAt: updatedAt,
  );
}

class _FakeNoteList extends NoteList {
  _FakeNoteList(this._note);

  Note _note;

  @override
  Future<List<Note>> build() async => [_note];

  @override
  Future<void> edit(String id, {String? title, String? content}) async {
    _note = _note.copyWith(
      title: title ?? _note.title,
      content: content ?? _note.content,
      updatedAt: DateTime.utc(2026, 5, 10, 12, 0, 30),
      syncStatus: 'pending',
      lastSyncedAt: null,
    );
    state = AsyncData([_note]);
  }

  void replace(Note note) {
    _note = note;
    state = AsyncData([_note]);
  }
}
