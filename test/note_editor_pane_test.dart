import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/widgets/note_editor_pane.dart';

/// Pumps a QuillEditor wrapped in the same delete-override Actions the note
/// editor pane installs, focused and ready for key events.
Future<QuillController> pumpEditorWithDeleteOverrides(
  WidgetTester tester, {
  String text = 'Hello world',
}) async {
  final controller = QuillController.basic();
  addTearDown(controller.dispose);
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  final scrollController = ScrollController();
  addTearDown(scrollController.dispose);

  controller.document.insert(0, text);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Actions(
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
          child: QuillEditor(
            controller: controller,
            focusNode: focusNode,
            scrollController: scrollController,
            config: const QuillEditorConfig(autoFocus: false),
          ),
        ),
      ),
    ),
  );
  focusNode.requestFocus();
  await tester.pump();
  return controller;
}

void _selectAll(QuillController controller) {
  controller.updateSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: controller.document.length,
    ),
    ChangeSource.local,
  );
}

void main() {
  group('noteBodyPreview', () {
    test('extracts plain text from a Quill Delta JSON', () {
      final delta = jsonEncode([
        {'insert': 'Hello '},
        {'insert': 'world', 'attributes': {'bold': true}},
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

      expect(reloaded.document.toPlainText(), controller.document.toPlainText());
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
      final attrs = reloaded.document
          .collectStyle(0, 5)
          .attributes;
      expect(attrs.containsKey('bold'), isTrue);
    });
  });

  group('SelectionSafeDeleteAction', () {
    testWidgets('backspace deletes a full-document selection and leaves the '
        'caret in bounds', (tester) async {
      final controller = await pumpEditorWithDeleteOverrides(tester);

      _selectAll(controller);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.document.toPlainText(), '\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('backspace deletes a near-full selection, keeping the tail',
        (tester) async {
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

    testWidgets('editor stays usable across repeated select-all delete cycles',
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
    });

    testWidgets('word-boundary delete (ctrl+backspace) removes a selection',
        (tester) async {
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
      SelectionSafeDeleteAction<DeleteToLineBreakIntent>(controller)
          .invoke(const DeleteToLineBreakIntent(forward: false));
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
