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

  testWidgets('controller inserts and toggles checkbox state on body lines', (
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
    textField.focusNode!.unfocus();
    editorController.toggleCheckbox();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n☐ Task');
    expect(textField.focusNode!.hasFocus, isTrue);
    expect(textField.controller!.selection.baseOffset, 'Title\n☐ '.length);

    editorController.toggleCheckbox();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n☑ Task');
    expect(textField.controller!.selection.baseOffset, 'Title\n☑ '.length);

    editorController.toggleCheckbox();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n☐ Task');
    expect(textField.controller!.selection.baseOffset, 'Title\n☐ '.length);
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

  testWidgets('tapping a checkbox marker toggles it in place', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteListProvider.overrideWith(
            () => _FakeNoteList(
              _note(
                title: 'Title',
                content: '☐ Task',
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

    final fieldFinder = find.byType(TextField);
    final textField = tester.widget<TextField>(fieldFinder);
    textField.controller!.selection = const TextSelection.collapsed(offset: 2);
    await tester.tap(find.byKey(const ValueKey('note-checkbox-icon-6')));
    await tester.pump();

    expect(textField.controller!.text, 'Title\n☑ Task');
    expect(textField.controller!.selection.baseOffset, 2);
    expect(textField.focusNode!.hasFocus, isTrue);
  });

  testWidgets('checkbox lines expose a hover target', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteListProvider.overrideWith(
            () => _FakeNoteList(
              _note(
                title: 'Title',
                content: '☐ Task',
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

    final mouseRegions = tester.widgetList<MouseRegion>(
      find.byType(MouseRegion),
    );
    expect(
      mouseRegions.any((region) => region.cursor == SystemMouseCursors.basic),
      isTrue,
    );
  });

  testWidgets('legacy checked checkboxes still toggle and normalize', (
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
                content: '☑ Task',
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

    final fieldFinder = find.byType(TextField);
    final textField = tester.widget<TextField>(fieldFinder);
    textField.controller!.selection = const TextSelection.collapsed(
      offset: 'Title\n☑ '.length,
    );
    editorController.toggleCheckbox();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n☐ Task');
  });

  testWidgets('formatting controller wraps selected text in markdown markers', (
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
                content: 'Important words',
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

    final fieldFinder = find.byType(TextField);
    final textField = tester.widget<TextField>(fieldFinder);
    const selectedStart = 'Title\n'.length;
    const selectedEnd = 'Title\nImportant'.length;
    textField.controller!.selection = const TextSelection(
      baseOffset: selectedStart,
      extentOffset: selectedEnd,
    );

    editorController.toggleBold();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n**Important** words');

    textField.controller!.selection = const TextSelection(
      baseOffset: selectedStart + 2,
      extentOffset: selectedEnd + 2,
    );
    editorController.toggleBold();
    await tester.pump();

    expect(textField.controller!.text, 'Title\nImportant words');
  });

  testWidgets('formatting controller inserts paired markers at cursor', (
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
                content: 'Body',
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

    final textField = tester.widget<TextField>(find.byType(TextField));
    textField.controller!.selection = const TextSelection.collapsed(
      offset: 'Title\nBody'.length,
    );

    editorController.toggleUnderline();
    await tester.pump();

    expect(textField.controller!.text, 'Title\nBody++++');
    expect(textField.controller!.selection.baseOffset, 'Title\nBody++'.length);
  });

  testWidgets('heading controls apply to plain body lines only', (
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
                content: 'Section\n- Item',
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

    final textField = tester.widget<TextField>(find.byType(TextField));
    textField.controller!.selection = const TextSelection.collapsed(
      offset: 'Title\nSection'.length,
    );
    editorController.toggleH1();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n# Section\n- Item');

    textField.controller!.selection = const TextSelection.collapsed(
      offset: 'Title\n# Section\n- Item'.length,
    );
    editorController.toggleH2();
    await tester.pump();

    expect(textField.controller!.text, 'Title\n# Section\n- Item');
  });

  test('stripNoteMarkdown removes inline, heading, and list markers', () {
    expect(
      stripNoteMarkdown('# **Big**\n- *item*\n☑ ++done++'),
      'Big\nitem\ndone',
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
