import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';

class NoteEditorPane extends ConsumerStatefulWidget {
  final String noteId;
  final bool autoFocusTitle;
  final VoidCallback? onDelete;

  const NoteEditorPane({
    super.key,
    required this.noteId,
    this.autoFocusTitle = false,
    this.onDelete,
  });

  @override
  ConsumerState<NoteEditorPane> createState() => _NoteEditorPaneState();
}

class _NoteEditorPaneState extends ConsumerState<NoteEditorPane> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _titleFocus = FocusNode();
  Timer? _debounce;
  String _lastSavedTitle = '';
  String _lastSavedContent = '';
  bool _initialized = false;

  static const _debounceDuration = Duration(milliseconds: 1000);
  static const _bullet = '• ';

  @override
  void dispose() {
    _debounce?.cancel();
    _flushIfDirty();
    _titleController.dispose();
    _contentController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _flushIfDirty() {
    final t = _titleController.text;
    final c = _contentController.text;
    if (!_initialized) return;
    if (t == _lastSavedTitle && c == _lastSavedContent) return;
    _lastSavedTitle = t;
    _lastSavedContent = c;
    ref.read(noteListProvider.notifier).edit(widget.noteId, title: t, content: c);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flushIfDirty);
  }

  void _toggleBullet() {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (!sel.isValid) return;
    final cursor = sel.isCollapsed ? sel.baseOffset : sel.start;
    final lineStart = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
    final lineEndRaw = text.indexOf('\n', cursor);
    final lineEnd = lineEndRaw < 0 ? text.length : lineEndRaw;
    final line = text.substring(lineStart, lineEnd);

    final String newText;
    final int newCursor;

    if (line.startsWith(_bullet)) {
      newText = text.substring(0, lineStart) +
          line.substring(_bullet.length) +
          text.substring(lineEnd);
      newCursor = (cursor - _bullet.length).clamp(
          lineStart, lineStart + line.length - _bullet.length);
    } else {
      newText =
          text.substring(0, lineStart) + _bullet + text.substring(lineStart);
      newCursor = cursor + _bullet.length;
    }

    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    _scheduleSave();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This note will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      _debounce?.cancel();
      _initialized = false;
      await ref.read(noteListProvider.notifier).delete(widget.noteId);
      if (context.mounted) widget.onDelete?.call();
    }
  }

  Note? _findNote(List<Note> notes) {
    for (final n in notes) {
      if (n.id == widget.noteId) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final asyncNotes = ref.watch(noteListProvider);

    return asyncNotes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notes) {
        final note = _findNote(notes);
        if (note == null) return const Center(child: Text('Note not found'));

        if (!_initialized) {
          _titleController.text = note.title;
          _contentController.text = note.content;
          _lastSavedTitle = note.title;
          _lastSavedContent = note.content;
          _initialized = true;
          if (widget.autoFocusTitle) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _titleFocus.requestFocus();
            });
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title area — visually distinct background
            Container(
              color: cs.surfaceContainer,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      focusNode: _titleFocus,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'Title',
                        hintStyle: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.3),
                          fontWeight: FontWeight.bold,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (_) => _scheduleSave(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 20,
                    tooltip: 'Delete note',
                    onPressed: () => _confirmDelete(context),
                  ),
                ],
              ),
            ),
            // Formatting toolbar
            Container(
              color: cs.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted),
                    iconSize: 18,
                    tooltip: 'Toggle bullet list',
                    visualDensity: VisualDensity.compact,
                    onPressed: _toggleBullet,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content area
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyLarge,
                inputFormatters: [_NoteBulletFormatter()],
                decoration: const InputDecoration(
                  hintText: 'Start writing…',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.all(16),
                ),
                onChanged: (_) => _scheduleSave(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NoteBulletFormatter extends TextInputFormatter {
  static const _bullet = '• ';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final inserted = newValue.text.length - oldValue.text.length;
    if (inserted != 1 || !newValue.selection.isCollapsed) return newValue;

    final cursor = newValue.selection.baseOffset;
    if (cursor == 0 || newValue.text[cursor - 1] != '\n') return newValue;

    final before = newValue.text.substring(0, cursor - 1);
    final prevLineStart = before.lastIndexOf('\n') + 1;
    final prevLine = before.substring(prevLineStart);

    if (!prevLine.startsWith(_bullet)) return newValue;

    if (prevLine == _bullet) {
      // Empty bullet line — remove bullet on Enter instead of continuing
      final newText = newValue.text.substring(0, prevLineStart) +
          '\n' +
          newValue.text.substring(cursor);
      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: prevLineStart + 1),
      );
    }

    // Continue bullet on new line
    final after = newValue.text.substring(cursor);
    if (after.startsWith(_bullet)) return newValue;
    final updated = newValue.text.substring(0, cursor) + _bullet + after;
    return TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: cursor + _bullet.length),
    );
  }
}
