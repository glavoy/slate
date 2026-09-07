import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/simple_list_providers.dart';
import 'rich_text_editor.dart';

const _debounceDuration = Duration(milliseconds: 1200);
const _idleBeforeRemoteSync = Duration(seconds: 3);

class SimpleListSection extends ConsumerStatefulWidget {
  const SimpleListSection({super.key});

  @override
  ConsumerState<SimpleListSection> createState() => _SimpleListSectionState();
}

class _SimpleListSectionState extends ConsumerState<SimpleListSection> {
  late final QuillController _quill;
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;
  String _lastSavedDocument = '';
  String _lastRemoteContent = '';
  DateTime _lastLocalEdit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _initialized = false;
  bool _applyingRemote = false;

  late final Map<Type, Action<Intent>> _deleteOverrides;

  String get _serializedContent => serializeDocument(_quill);
  bool get _isDirty => _initialized && _serializedContent != _lastSavedDocument;

  @override
  void initState() {
    super.initState();
    _quill = createSelectionSafeQuillController();
    _deleteOverrides = {
      DeleteCharacterIntent: SelectionSafeDeleteAction<DeleteCharacterIntent>(
        _quill,
      ),
      DeleteToNextWordBoundaryIntent:
          SelectionSafeDeleteAction<DeleteToNextWordBoundaryIntent>(_quill),
      DeleteToLineBreakIntent:
          SelectionSafeDeleteAction<DeleteToLineBreakIntent>(_quill),
    };
    _quill.addListener(_onDocumentChanged);
  }

  @override
  void deactivate() {
    _debounce?.cancel();
    _flushIfDirty();
    super.deactivate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _quill.removeListener(_onDocumentChanged);
    _quill.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDocumentChanged() {
    if (!_initialized || _applyingRemote || !_isDirty) return;
    _lastLocalEdit = DateTime.now();
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flushIfDirty);
  }

  void _flushIfDirty() {
    if (!_isDirty) return;
    final content = _serializedContent;
    _lastSavedDocument = content;
    _lastRemoteContent = content;
    ref.read(simpleListNotifierProvider.notifier).save(content);
  }

  void _initialize(String content) {
    _applyingRemote = true;
    try {
      _quill.document = documentFromStoredContent(content);
    } finally {
      _applyingRemote = false;
    }
    _lastSavedDocument = _serializedContent;
    _lastRemoteContent = content;
    _initialized = true;
  }

  void _applyRemote(String remoteContent) {
    if (remoteContent == _lastRemoteContent || _focusNode.hasFocus) return;
    if (_isDirty || (_debounce?.isActive ?? false)) return;
    if (DateTime.now().difference(_lastLocalEdit) < _idleBeforeRemoteSync) {
      return;
    }
    _applyingRemote = true;
    try {
      final previousOffset = _quill.selection.baseOffset;
      _quill.document = documentFromStoredContent(remoteContent);
      final maxOffset = _quill.document.length - 1;
      _quill.updateSelection(
        TextSelection.collapsed(
          offset: previousOffset.clamp(0, maxOffset < 0 ? 0 : maxOffset),
        ),
        ChangeSource.local,
      );
    } finally {
      _applyingRemote = false;
    }
    _lastSavedDocument = _serializedContent;
    _lastRemoteContent = remoteContent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncList = ref.watch(simpleListNotifierProvider);

    ref.listen(simpleListNotifierProvider, (previous, next) {
      next.whenData((list) {
        if (!_initialized) {
          _initialize(list.content);
        } else {
          _applyRemote(list.content);
        }
      });
    });

    return asyncList.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text('To Do error: $error'),
      ),
      data: (list) {
        if (!_initialized) _initialize(list.content);
        return Column(
          children: [
            Expanded(
              child: Actions(
                actions: _deleteOverrides,
                child: QuillEditor(
                  controller: _quill,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  config: QuillEditorConfig(
                    placeholder: 'Start writing…',
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    expands: true,
                    scrollable: true,
                    customStyles: DefaultStyles(
                      paragraph: DefaultTextBlockStyle(
                        (theme.textTheme.bodyLarge ??
                                const TextStyle(fontSize: 16))
                            .copyWith(height: 1.25),
                        const HorizontalSpacing(0, 0),
                        const VerticalSpacing(0, 0),
                        const VerticalSpacing(0, 0),
                        null,
                      ),
                      h2: DefaultTextBlockStyle(
                        (theme.textTheme.bodyLarge ??
                                const TextStyle(fontSize: 16))
                            .copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                        const HorizontalSpacing(0, 0),
                        const VerticalSpacing(6, 0),
                        const VerticalSpacing(0, 0),
                        null,
                      ),
                    ),
                    // ignore: experimental_member_use
                    onKeyPressed: (event, _) =>
                        handleSelectionSafeDeleteKey(_quill, event),
                  ),
                ),
              ),
            ),
            RichTextFormatToolbar(
              controller: _quill,
              editorFocusNode: _focusNode,
            ),
          ],
        );
      },
    );
  }
}
