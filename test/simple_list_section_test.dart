import 'package:flutter/material.dart';
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

  void emit(String content) {
    state = AsyncData(_list(content));
  }

  static SimpleList _list(String content) => SimpleList(
    userId: 'user-1',
    content: content,
    updatedAt: DateTime.now().toUtc(),
  );
}

Future<_FakeSimpleListNotifier> _pumpQuickList(
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
      child: const MaterialApp(
        home: Scaffold(body: SimpleListSection()),
      ),
    ),
  );
  // Let the async provider deliver its first value.
  await tester.pumpAndSettle();
  return fake;
}

TextField _textField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  testWidgets('remote update is not applied while the field is focused',
      (tester) async {
    final fake = await _pumpQuickList(tester, initialContent: '- one\n- two');
    expect(_textField(tester).controller!.text, '- one\n- two');

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(_textField(tester).focusNode!.hasFocus, isTrue);

    fake.emit('- remote change');
    await tester.pump();

    expect(_textField(tester).controller!.text, '- one\n- two');
  });

  testWidgets('remote update applies while unfocused and clean, preserving a '
      'clamped cursor', (tester) async {
    final fake = await _pumpQuickList(
      tester,
      initialContent: '- a longer initial list\n- second line',
    );

    // Place the cursor mid-text, then move focus away.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final controller = _textField(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 20);
    _textField(tester).focusNode!.unfocus();
    await tester.pump();

    fake.emit('- short');
    await tester.pump();

    expect(controller.text, '- short');
    expect(controller.selection.isCollapsed, isTrue);
    // 20 clamped into the new, shorter text.
    expect(controller.selection.baseOffset, '- short'.length);
  });

  testWidgets('remote update is not applied while an edit is pending save',
      (tester) async {
    final fake = await _pumpQuickList(tester, initialContent: '- one');

    await tester.enterText(find.byType(TextField), '- one\n- two');
    await tester.pump();

    _textField(tester).focusNode!.unfocus();
    await tester.pump();

    fake.emit('- remote change');
    await tester.pump();

    expect(_textField(tester).controller!.text, '- one\n- two');

    // Let the debounce fire so no timer leaks out of the test.
    await tester.pump(const Duration(seconds: 2));
    expect(fake.saved, contains('- one\n- two'));
  });

  testWidgets('an edit still inside the debounce window is flushed on dispose',
      (tester) async {
    final fake = await _pumpQuickList(tester, initialContent: '- one');

    await tester.enterText(find.byType(TextField), '- one\n- milk');
    await tester.pump();
    expect(fake.saved, isEmpty);

    // Tear the widget down before the 1200ms debounce fires.
    await tester.pumpWidget(const SizedBox());

    expect(fake.saved, ['- one\n- milk']);
  });
}
