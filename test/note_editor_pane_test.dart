import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/models/note.dart';
import 'package:slate/widgets/note_editor_pane.dart';

/// Pumps a QuillEditor wrapped in the same delete-override Actions the note
/// editor pane installs, focused and ready for key events.
Future<QuillController> pumpEditorWithDeleteOverrides(
  WidgetTester tester, {
  String text = 'Hello world',
  bool includeDeleteOverrides = true,
  bool useHardwareDeleteHandler = false,
}) async {
  final controller = QuillController.basic();
  addTearDown(controller.dispose);
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  final scrollController = ScrollController();
  addTearDown(scrollController.dispose);

  controller.document.insert(0, text);

  final editor = QuillEditor(
    controller: controller,
    focusNode: focusNode,
    scrollController: scrollController,
    config: QuillEditorConfig(
      autoFocus: false,
      // ignore: experimental_member_use
      onKeyPressed: useHardwareDeleteHandler
          ? (event, _) => handleSelectionSafeDeleteKey(controller, event)
          : null,
    ),
  );
  final body = includeDeleteOverrides
      ? Actions(
          actions: {
            DeleteCharacterIntent:
                SelectionSafeDeleteAction<DeleteCharacterIntent>(controller),
            DeleteToNextWordBoundaryIntent:
                SelectionSafeDeleteAction<DeleteToNextWordBoundaryIntent>(
                  controller,
                ),
            DeleteToLineBreakIntent:
                SelectionSafeDeleteAction<DeleteToLineBreakIntent>(controller),
          },
          child: editor,
        )
      : editor;

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  focusNode.requestFocus();
  await tester.pump();
  return controller;
}

void _selectAll(QuillController controller) {
  controller.updateSelection(
    TextSelection(baseOffset: 0, extentOffset: controller.document.length),
    ChangeSource.local,
  );
}

Note _note({String title = '', String content = ''}) => Note(
  id: 'note-1',
  userId: 'user-1',
  title: title,
  content: content,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('noteBodyPreview', () {
    test('extracts plain text from a Quill Delta JSON', () {
      final delta = jsonEncode([
        {'insert': 'Hello '},
        {
          'insert': 'world',
          'attributes': {'bold': true},
        },
        {'insert': '\nSecond line\n'},
      ]);
      expect(noteBodyPreview(delta), 'Hello world\nSecond line\n');
    });

    test('returns empty string for empty content', () {
      expect(noteBodyPreview(''), '');
    });

    test('falls back to the raw string for legacy plain-text content', () {
      const legacy = 'This is a legacy note without Quill encoding';
      expect(noteBodyPreview(legacy), legacy);
    });

    test('falls back to the raw string for malformed JSON', () {
      const garbage = '{not valid json';
      expect(noteBodyPreview(garbage), garbage);
    });

    test('falls back for JSON that is not a Delta list', () {
      const obj = '{"title":"hi"}';
      expect(noteBodyPreview(obj), obj);
    });
  });

  group('Quill Delta round-trip', () {
    test('empty controller serializes and deserializes without throwing', () {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);

      final encoded = jsonEncode(controller.document.toDelta().toJson());
      final decoded = jsonDecode(encoded);
      expect(decoded, isA<List<dynamic>>());

      final reloaded = QuillController(
        document: Document.fromJson(decoded as List),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(reloaded.dispose);

      expect(
        reloaded.document.toPlainText(),
        controller.document.toPlainText(),
      );
    });

    test('content with formatting survives a round trip', () {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);

      controller.document.insert(0, 'Hello');
      controller.formatText(0, 5, Attribute.bold);

      final encoded = jsonEncode(controller.document.toDelta().toJson());
      final reloaded = QuillController(
        document: Document.fromJson(jsonDecode(encoded) as List),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(reloaded.dispose);

      expect(reloaded.document.toPlainText().trim(), 'Hello');
      final attrs = reloaded.document.collectStyle(0, 5).attributes;
      expect(attrs.containsKey('bold'), isTrue);
    });
  });

  group('noteListDisplayText', () {
    test('uses an explicit title and the first body line as preview', () {
      final display = noteListDisplayText(
        _note(title: '  Project plan  ', content: 'First step\nSecond step'),
      );

      expect(display.title, 'Project plan');
      expect(display.preview, 'First step');
    });

    test('derives a missing title and advances preview to the next line', () {
      final display = noteListDisplayText(
        _note(content: '\n  Meeting notes  \n\nDiscuss schedule\nFollow up'),
      );

      expect(display.title, 'Meeting notes');
      expect(display.preview, 'Discuss schedule');
    });

    test('does not duplicate a one-line derived title in the preview', () {
      final display = noteListDisplayText(_note(content: 'Only line'));

      expect(display.title, 'Only line');
      expect(display.preview, 'No content');
    });

    test('uses untitled and no-content labels for an empty note', () {
      final display = noteListDisplayText(_note());

      expect(display.title, '(Untitled)');
      expect(display.preview, 'No content');
    });
  });

  testWidgets('title Next action focuses the body and preserves its cursor', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.document.insert(0, 'Existing body');
    controller.updateSelection(
      const TextSelection.collapsed(offset: 8),
      ChangeSource.local,
    );
    final titleFocusNode = FocusNode();
    addTearDown(titleFocusNode.dispose);
    final bodyFocusNode = FocusNode();
    addTearDown(bodyFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                focusNode: titleFocusNode,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => focusQuillEditor(controller, bodyFocusNode),
              ),
              Focus(focusNode: bodyFocusNode, child: const SizedBox()),
            ],
          ),
        ),
      ),
    );
    titleFocusNode.requestFocus();
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(bodyFocusNode.hasFocus, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  group('SelectionSafeDeleteAction', () {
    testWidgets('hardware Delete removes a full-document selection before '
        'the platform text-input pipeline', (tester) async {
      final controller = await pumpEditorWithDeleteOverrides(
        tester,
        includeDeleteOverrides: false,
        useHardwareDeleteHandler: true,
      );

      _selectAll(controller);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(controller.document.toPlainText(), '\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('hardware Backspace removes a full-document selection before '
        'the platform text-input pipeline', (tester) async {
      final controller = await pumpEditorWithDeleteOverrides(
        tester,
        includeDeleteOverrides: false,
        useHardwareDeleteHandler: true,
      );

      _selectAll(controller);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.document.toPlainText(), '\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('backspace deletes a full-document selection and leaves the '
        'caret in bounds', (tester) async {
      final controller = await pumpEditorWithDeleteOverrides(tester);

      _selectAll(controller);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.document.toPlainText(), '\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('backspace deletes a near-full selection, keeping the tail', (
      tester,
    ) async {
      final controller = await pumpEditorWithDeleteOverrides(tester);

      controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 8),
        ChangeSource.local,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.document.toPlainText(), 'rld\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets(
      'editor stays usable across repeated select-all delete cycles',
      (tester) async {
        final controller = await pumpEditorWithDeleteOverrides(tester);

        _selectAll(controller);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.document.toPlainText(), '\n');

        controller.replaceText(
          0,
          0,
          'Second round',
          const TextSelection.collapsed(offset: 12),
        );
        await tester.pump();
        expect(controller.document.toPlainText(), 'Second round\n');

        _selectAll(controller);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(controller.document.toPlainText(), '\n');
        expect(controller.selection, const TextSelection.collapsed(offset: 0));
      },
    );

    testWidgets('word-boundary delete (ctrl+backspace) removes a selection', (
      tester,
    ) async {
      final controller = await pumpEditorWithDeleteOverrides(tester);

      _selectAll(controller);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(controller.document.toPlainText(), '\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('line-break delete intent removes a selection', (tester) async {
      final controller = await pumpEditorWithDeleteOverrides(tester);

      controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
        ChangeSource.local,
      );
      SelectionSafeDeleteAction<DeleteToLineBreakIntent>(
        controller,
      ).invoke(const DeleteToLineBreakIntent(forward: false));
      await tester.pump();

      expect(controller.document.toPlainText(), ' world\n');
    });

    testWidgets('collapsed-cursor backspace still delegates to the quill '
        'default', (tester) async {
      final controller = await pumpEditorWithDeleteOverrides(tester);

      controller.updateSelection(
        const TextSelection.collapsed(offset: 11),
        ChangeSource.local,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.document.toPlainText(), 'Hello worl\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 10));
    });
  });
}
