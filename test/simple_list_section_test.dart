import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slate/models/simple_list.dart';
import 'package:slate/providers/simple_list_providers.dart';
import 'package:slate/widgets/simple_list_section.dart';

class _FakeSimpleListNotifier extends SimpleListNotifier {
  _FakeSimpleListNotifier(this.initialContent);

  final String initialContent;
  final saved = <String>[];

  @override
  Future<SimpleList> build() async => _list(initialContent);

  @override
  Future<void> save(String content) async {
    saved.add(content);
  }

  void emit(String content) => state = AsyncData(_list(content));

  static SimpleList _list(String content) => SimpleList(
    userId: 'user-1',
    content: content,
    updatedAt: DateTime.now().toUtc(),
  );
}

Future<_FakeSimpleListNotifier> _pumpTodoList(
  WidgetTester tester, {
  required String initialContent,
}) async {
  late _FakeSimpleListNotifier fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        simpleListProvider.overrideWith(() {
          fake = _FakeSimpleListNotifier(initialContent);
          return fake;
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: SimpleListSection())),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

QuillController _controller(WidgetTester tester) =>
    tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

void main() {
  testWidgets('shows stored plain text without list conversion', (
    tester,
  ) async {
    await _pumpTodoList(tester, initialContent: '- groceries\n• call Sam');

    expect(
      _controller(tester).document.toPlainText(),
      '- groceries\n• call Sam\n',
    );
    expect(_controller(tester).getSelectionStyle().attributes, isEmpty);
  });

  testWidgets('restores formatted Delta content', (tester) async {
    final content = jsonEncode([
      {'insert': 'Important'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
    ]);
    await _pumpTodoList(tester, initialContent: content);

    final controller = _controller(tester);
    expect(controller.document.toPlainText(), 'Important\n');
    expect(controller.document.toDelta().toJson(), jsonDecode(content));
  });

  testWidgets('toolbar formats the active line and saves Delta JSON', (
    tester,
  ) async {
    final fake = await _pumpTodoList(tester, initialContent: 'Buy milk');
    final controller = _controller(tester);
    controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );

    await tester.tap(find.byTooltip('Checkbox'));
    await tester.pump();
    expect(
      controller.getSelectionStyle().attributes[Attribute.list.key]?.value,
      Attribute.unchecked.value,
    );

    controller.replaceText(
      0,
      0,
      'Weekly: ',
      const TextSelection.collapsed(offset: 8),
    );
    await tester.pump(const Duration(milliseconds: 1300));

    expect(fake.saved, hasLength(1));
    expect(jsonDecode(fake.saved.single), isA<List<dynamic>>());
  });

  testWidgets('remote updates do not replace a focused document', (
    tester,
  ) async {
    final fake = await _pumpTodoList(tester, initialContent: 'Local list');
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    expect(
      tester.widget<QuillEditor>(find.byType(QuillEditor)).focusNode.hasFocus,
      isTrue,
    );

    fake.emit('Remote list');
    await tester.pump();

    expect(_controller(tester).document.toPlainText(), 'Local list\n');
  });

  testWidgets('an edit inside the debounce window flushes on dispose', (
    tester,
  ) async {
    final fake = await _pumpTodoList(tester, initialContent: 'One');
    final controller = _controller(tester);
    controller.replaceText(
      3,
      0,
      ' more',
      const TextSelection.collapsed(offset: 8),
    );
    await tester.pump();
    expect(fake.saved, isEmpty);

    await tester.pumpWidget(const SizedBox());
    expect(fake.saved, hasLength(1));
    expect(jsonDecode(fake.saved.single), isA<List<dynamic>>());
  });
}
