import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/widgets/note_editor_pane.dart';

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
}
