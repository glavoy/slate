import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';

/// Allows a parent AppBar to invoke actions inside the pane without a GlobalKey.
/// The pane registers its callbacks on init and unregisters on dispose.
/// A generation counter prevents a newly registered pane from being accidentally
/// unregistered by the dispose of an outgoing pane when the note selection changes.
class NoteEditorController {
  int _generation = 0;
  VoidCallback? _toggleBulletFn;
  Future<void> Function(BuildContext)? _deleteFn;

  int _register({
    required VoidCallback toggleBullet,
    required Future<void> Function(BuildContext) delete,
  }) {
    _toggleBulletFn = toggleBullet;
    _deleteFn = delete;
    return ++_generation;
  }

  void _unregister(int gen) {
    if (_generation == gen) {
      _toggleBulletFn = null;
      _deleteFn = null;
    }
  }

  void toggleBullet() => _toggleBulletFn?.call();
  Future<void> confirmDelete(BuildContext context) =>
      _deleteFn?.call(context) ?? Future.value();
}

class NoteEditorPane extends ConsumerStatefulWidget {
  final String noteId;
  final bool autoFocusTitle;
  final VoidCallback? onDelete;
  final NoteEditorController? controller;

  const NoteEditorPane({
    super.key,
    required this.noteId,
    this.autoFocusTitle = false,
    this.onDelete,
    this.controller,
  });

  @override
  ConsumerState<NoteEditorPane> createState() => _NoteEditorPaneState();
}

class _NoteEditorPaneState extends ConsumerState<NoteEditorPane> {
  late final _NoteController _controller;
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _lastSavedTitle = '';
  String _lastSavedContent = '';
  bool _initialized = false;
  int _controllerGeneration = 0;

  static const _debounceDuration = Duration(milliseconds: 1000);
  static const _bullet = '• ';

  @override
  void initState() {
    super.initState();
    _controller = _NoteController();
    if (widget.controller != null) {
      _controllerGeneration = widget.controller!._register(
        toggleBullet: _toggleBullet,
        delete: _confirmDelete,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flushIfDirty();
    widget.controller?._unregister(_controllerGeneration);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _title {
    final text = _controller.text;
    final i = text.indexOf('\n');
    return i == -1 ? text : text.substring(0, i);
  }

  String get _content {
    final text = _controller.text;
    final i = text.indexOf('\n');
    return i == -1 ? '' : text.substring(i + 1);
  }

  static String _buildInitial(Note note) {
    if (note.title.isEmpty && note.content.isEmpty) return '';
    if (note.title.isEmpty) return note.content;
    if (note.content.isEmpty) return note.title;
    return '${note.title}\n${note.content}';
  }

  void _flushIfDirty() {
    if (!_initialized) return;
    final t = _title;
    final c = _content;
    if (t == _lastSavedTitle && c == _lastSavedContent) return;
    _lastSavedTitle = t;
    _lastSavedContent = c;
    ref
        .read(noteListProvider.notifier)
        .edit(widget.noteId, title: t, content: c);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flushIfDirty);
  }

  void _toggleBullet() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final cursor = sel.isCollapsed ? sel.baseOffset : sel.start;

    // Only apply to body lines (after the title's first \n)
    final firstNewline = text.indexOf('\n');
    if (firstNewline == -1 || cursor <= firstNewline) return;

    final lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
    final lineEndRaw = text.indexOf('\n', cursor);
    final lineEnd = lineEndRaw < 0 ? text.length : lineEndRaw;
    final line = text.substring(lineStart, lineEnd);

    final String newText;
    final int newCursor;

    if (line.startsWith(_bullet)) {
      newText = text.substring(0, lineStart) +
          line.substring(_bullet.length) +
          text.substring(lineEnd);
      newCursor = (cursor - _bullet.length)
          .clamp(lineStart, lineStart + line.length - _bullet.length);
    } else {
      newText = text.substring(0, lineStart) +
          _bullet +
          text.substring(lineStart);
      newCursor = cursor + _bullet.length;
    }

    _controller.value = TextEditingValue(
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
        content: const Text('This note will be moved to Trash.'),
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
    final bodyFontSize = theme.textTheme.bodyLarge?.fontSize ?? 16.0;
    final asyncNotes = ref.watch(noteListProvider);

    return asyncNotes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notes) {
        final note = _findNote(notes);
        if (note == null) return const Center(child: Text('Note not found'));

        if (!_initialized) {
          _controller.text = _buildInitial(note);
          _lastSavedTitle = note.title;
          _lastSavedContent = note.content;
          _initialized = true;
          if (widget.autoFocusTitle) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focusNode.requestFocus();
            });
          }
        }

        return TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: null,
          expands: true,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          style: theme.textTheme.bodyLarge,
          inputFormatters: [_NoteBulletFormatter()],
          decoration: InputDecoration(
            hintText: 'Title',
            hintStyle: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.3),
              fontWeight: FontWeight.bold,
              fontSize: bodyFontSize * 1.3,
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.all(16),
          ),
          onChanged: (_) => _scheduleSave(),
        );
      },
    );
  }
}

// Renders the first line (title) bold at 1.3× size; body lines use the base style.
class _NoteController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle();
    final titleStyle = base.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: (base.fontSize ?? 16.0) * 1.3,
    );

    final text = this.text;
    final newlineIndex = text.indexOf('\n');

    if (newlineIndex == -1) {
      return TextSpan(text: text, style: titleStyle);
    }

    return TextSpan(
      children: [
        TextSpan(text: text.substring(0, newlineIndex), style: titleStyle),
        TextSpan(text: text.substring(newlineIndex), style: base),
      ],
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

    // Continue bullet on next line
    final after = newValue.text.substring(cursor);
    if (after.startsWith(_bullet)) return newValue;
    final updated = newValue.text.substring(0, cursor) + _bullet + after;
    return TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: cursor + _bullet.length),
    );
  }
}
