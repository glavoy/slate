import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';
import '../providers/supabase_provider.dart';
import '../repositories/note_repository.dart';

const String _uncheckedMarker = '☐ ';
const String _checkedMarker = '☑ ';
const String _legacyCheckedMarker = '☒ ';
const String _bulletMarker = '- ';
const String _h1Marker = '# ';
const String _h2Marker = '## ';

String? _checkboxMarkerPrefix(String line) {
  if (line.startsWith(_uncheckedMarker)) return _uncheckedMarker;
  if (line.startsWith(_checkedMarker)) return _checkedMarker;
  if (line.startsWith(_legacyCheckedMarker)) return _legacyCheckedMarker;
  return null;
}

bool _isCheckedMarker(String marker) =>
    marker == _checkedMarker || marker == _legacyCheckedMarker;

String _normalizeCheckedMarkers(String text) =>
    text.replaceAll(_legacyCheckedMarker, _checkedMarker);

String stripNoteMarkdown(String text) {
  return text
      .split('\n')
      .map((line) {
        var stripped = line;
        final checkboxMarker = _checkboxMarkerPrefix(stripped);
        if (checkboxMarker != null) {
          stripped = stripped.substring(checkboxMarker.length);
        } else if (stripped.startsWith(_bulletMarker)) {
          stripped = stripped.substring(_bulletMarker.length);
        } else if (stripped.startsWith(_h2Marker)) {
          stripped = stripped.substring(_h2Marker.length);
        } else if (stripped.startsWith(_h1Marker)) {
          stripped = stripped.substring(_h1Marker.length);
        }
        return stripped
            .replaceAllMapped(
              RegExp(r'\*\*([^*]+)\*\*'),
              (match) => match.group(1)!,
            )
            .replaceAllMapped(
              RegExp(r'\+\+([^+]+)\+\+'),
              (match) => match.group(1)!,
            )
            .replaceAllMapped(
              RegExp(r'\*([^*]+)\*'),
              (match) => match.group(1)!,
            );
      })
      .join('\n');
}

/// Allows a parent AppBar to invoke actions inside the pane without a GlobalKey.
/// The pane registers its callbacks on init and unregisters on dispose.
/// A generation counter prevents a newly registered pane from being accidentally
/// unregistered by the dispose of an outgoing pane when the note selection changes.
class NoteEditorController {
  int _generation = 0;
  VoidCallback? _toggleCheckboxFn;
  VoidCallback? _focusTitleFn;
  Future<void> Function(BuildContext)? _deleteFn;
  VoidCallback? _toggleBoldFn;
  VoidCallback? _toggleItalicFn;
  VoidCallback? _toggleUnderlineFn;
  VoidCallback? _toggleH1Fn;
  VoidCallback? _toggleH2Fn;

  int _register({
    required VoidCallback toggleCheckbox,
    required VoidCallback toggleBullet,
    required VoidCallback toggleBold,
    required VoidCallback toggleItalic,
    required VoidCallback toggleUnderline,
    required VoidCallback toggleH1,
    required VoidCallback toggleH2,
    required VoidCallback focusTitle,
    required Future<void> Function(BuildContext) delete,
  }) {
    _toggleCheckboxFn = toggleCheckbox;
    _toggleBulletFn = toggleBullet;
    _toggleBoldFn = toggleBold;
    _toggleItalicFn = toggleItalic;
    _toggleUnderlineFn = toggleUnderline;
    _toggleH1Fn = toggleH1;
    _toggleH2Fn = toggleH2;
    _focusTitleFn = focusTitle;
    _deleteFn = delete;
    return ++_generation;
  }

  void _unregister(int gen) {
    if (_generation == gen) {
      _toggleCheckboxFn = null;
      _toggleBulletFn = null;
      _toggleBoldFn = null;
      _toggleItalicFn = null;
      _toggleUnderlineFn = null;
      _toggleH1Fn = null;
      _toggleH2Fn = null;
      _focusTitleFn = null;
      _deleteFn = null;
    }
  }

  VoidCallback? _toggleBulletFn;

  void toggleCheckbox() => _toggleCheckboxFn?.call();
  void toggleBullet() => _toggleBulletFn?.call();
  void toggleBold() => _toggleBoldFn?.call();
  void toggleItalic() => _toggleItalicFn?.call();
  void toggleUnderline() => _toggleUnderlineFn?.call();
  void toggleH1() => _toggleH1Fn?.call();
  void toggleH2() => _toggleH2Fn?.call();
  void focusTitle() => _focusTitleFn?.call();
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
  static const _editorPadding = EdgeInsets.all(16);

  late final _NoteController _controller;
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _lastSavedTitle = '';
  String _lastSavedContent = '';
  bool _initialized = false;
  bool _autoFocusRequested = false;
  bool _hasUnsavedEditorChanges = false;
  int _controllerGeneration = 0;
  DateTime? _lastAppliedRemoteUpdate;
  Future<void> Function(String, {String? title, String? content})?
  _saveWithoutProviderRefresh;

  static const _debounceDuration = Duration(milliseconds: 1000);

  @override
  void initState() {
    super.initState();
    _controller = _NoteController(
      onToggleMarker: (offset, preserve) =>
          _toggleMarkerAt(offset, preserveSelection: preserve),
    );
    _focusNode.addListener(_handleFocusChanged);
    if (widget.controller != null) {
      _controllerGeneration = widget.controller!._register(
        toggleCheckbox: _toggleCheckboxAtCursor,
        toggleBullet: _toggleBulletAtCursor,
        toggleBold: _toggleBold,
        toggleItalic: _toggleItalic,
        toggleUnderline: _toggleUnderline,
        toggleH1: _toggleH1,
        toggleH2: _toggleH2,
        focusTitle: _focusTitle,
        delete: _confirmDelete,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flushIfDirty(updateUi: false, refreshProvider: false);
    _focusNode.removeListener(_handleFocusChanged);
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
    final content = _normalizeCheckedMarkers(note.content);
    if (note.title.isEmpty && content.isEmpty) return '';
    if (note.title.isEmpty) return content;
    if (content.isEmpty) return note.title;
    return '${note.title}\n$content';
  }

  void _flushIfDirty({bool updateUi = true, bool refreshProvider = true}) {
    if (!_initialized) return;
    final t = _title;
    final c = _content;
    if (t == _lastSavedTitle && c == _lastSavedContent) {
      if (_hasUnsavedEditorChanges) {
        if (updateUi && mounted) {
          setState(() => _hasUnsavedEditorChanges = false);
        } else {
          _hasUnsavedEditorChanges = false;
        }
      }
      return;
    }
    _lastSavedTitle = t;
    _lastSavedContent = c;
    if (updateUi && mounted) {
      setState(() => _hasUnsavedEditorChanges = false);
    } else {
      _hasUnsavedEditorChanges = false;
    }
    if (refreshProvider) {
      ref
          .read(noteListProvider.notifier)
          .edit(widget.noteId, title: t, content: c);
    } else {
      _saveWithoutProviderRefresh?.call(widget.noteId, title: t, content: c);
    }
  }

  bool get _isDirty =>
      _initialized &&
      (_title != _lastSavedTitle || _content != _lastSavedContent);

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus && mounted) {
      setState(() {});
    }
  }

  void _scheduleSave() {
    if (!_hasUnsavedEditorChanges) {
      setState(() => _hasUnsavedEditorChanges = true);
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flushIfDirty);
  }

  void _requestTitleFocus() {
    if (!widget.autoFocusTitle || _autoFocusRequested) return;
    _autoFocusRequested = true;
    _focusTitle();
  }

  void _focusTitle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  /// Toggle/insert a checkbox marker on the body line containing [offset].
  /// [preserveSelection] keeps the cursor where it was (used when tapping an
  /// icon directly). Without it the cursor lands just after the new marker.
  void _toggleMarkerAt(int offset, {TextSelection? preserveSelection}) {
    final text = _controller.text;
    final firstNewline = text.indexOf('\n');

    final String prepared;
    final int workingOffset;
    if (firstNewline == -1) {
      prepared = '$text\n';
      workingOffset = prepared.length;
    } else if (offset <= firstNewline) {
      prepared = text;
      workingOffset = firstNewline + 1;
    } else {
      prepared = text;
      workingOffset = offset.clamp(firstNewline + 1, prepared.length);
    }

    final lineStart = prepared.lastIndexOf('\n', workingOffset - 1) + 1;
    final lineEndRaw = prepared.indexOf('\n', workingOffset);
    final lineEnd = lineEndRaw < 0 ? prepared.length : lineEndRaw;
    final line = prepared.substring(lineStart, lineEnd);
    final cbMarker = _checkboxMarkerPrefix(line);
    final isBullet = line.startsWith(_bulletMarker);

    final String replacement;
    final int cursorAfter;
    if (cbMarker != null) {
      // Has a checkbox marker — toggle checked ↔ unchecked.
      final nextMarker = cbMarker == _uncheckedMarker
          ? _checkedMarker
          : _uncheckedMarker;
      replacement = nextMarker + line.substring(cbMarker.length);
      cursorAfter = _cursorAfterMarkerSwap(
        cursor: workingOffset,
        lineStart: lineStart,
        oldMarker: cbMarker,
        newMarker: nextMarker,
      );
    } else if (isBullet) {
      // bullet line → convert to unchecked checkbox
      replacement = _uncheckedMarker + line.substring(_bulletMarker.length);
      cursorAfter = _cursorAfterMarkerSwap(
        cursor: workingOffset,
        lineStart: lineStart,
        oldMarker: _bulletMarker,
        newMarker: _uncheckedMarker,
      );
    } else {
      // plain line → add unchecked checkbox
      replacement = _uncheckedMarker + line;
      cursorAfter = lineStart + _uncheckedMarker.length;
    }

    final newText =
        prepared.substring(0, lineStart) +
        replacement +
        prepared.substring(lineEnd);

    final TextSelection newSelection;
    if (preserveSelection != null && preserveSelection.isValid) {
      newSelection = TextSelection(
        baseOffset: preserveSelection.baseOffset.clamp(0, newText.length),
        extentOffset: preserveSelection.extentOffset.clamp(0, newText.length),
      );
    } else {
      newSelection = TextSelection.collapsed(
        offset: cursorAfter.clamp(0, newText.length),
      );
    }

    _focusNode.requestFocus();
    if (preserveSelection != null) {
      // Lock the selection so the TextField's TapGestureRecognizer cannot
      // overwrite it, regardless of the order gesture callbacks fire.
      // Released after the next frame once all gesture processing is done.
      _controller._selectionLock = newSelection;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller._selectionLock = null;
      });
    }
    _controller.value = TextEditingValue(
      text: newText,
      selection: newSelection,
    );
    _scheduleSave();
  }

  int _cursorAfterMarkerSwap({
    required int cursor,
    required int lineStart,
    required String oldMarker,
    required String newMarker,
  }) {
    if (cursor <= lineStart + oldMarker.length) {
      return lineStart + newMarker.length;
    }
    return cursor - oldMarker.length + newMarker.length;
  }

  void _toggleCheckboxAtCursor() {
    final sel = _controller.selection;
    final offset = sel.isValid
        ? (sel.isCollapsed ? sel.baseOffset : sel.start)
        : _controller.text.length;
    _toggleMarkerAt(offset);
  }

  void _replaceSelection(String text, TextSelection selection) {
    _focusNode.requestFocus();
    _controller.value = TextEditingValue(text: text, selection: selection);
    _scheduleSave();
  }

  void _toggleInlineMarker(String marker) {
    final text = _controller.text;
    final rawSelection = _controller.selection;
    final selection = rawSelection.isValid
        ? rawSelection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start;
    final end = selection.end;

    if (selection.isCollapsed) {
      final updated = text.replaceRange(start, end, marker + marker);
      _replaceSelection(
        updated,
        TextSelection.collapsed(offset: start + marker.length),
      );
      return;
    }

    final hasWrappingMarkers =
        start >= marker.length &&
        end + marker.length <= text.length &&
        text.substring(start - marker.length, start) == marker &&
        text.substring(end, end + marker.length) == marker;

    if (hasWrappingMarkers) {
      final updated =
          text.substring(0, start - marker.length) +
          text.substring(start, end) +
          text.substring(end + marker.length);
      _replaceSelection(
        updated,
        TextSelection(
          baseOffset: start - marker.length,
          extentOffset: end - marker.length,
        ),
      );
      return;
    }

    final updated =
        text.substring(0, start) +
        marker +
        text.substring(start, end) +
        marker +
        text.substring(end);
    _replaceSelection(
      updated,
      TextSelection(
        baseOffset: start + marker.length,
        extentOffset: end + marker.length,
      ),
    );
  }

  void _toggleBold() => _toggleInlineMarker('**');

  void _toggleItalic() => _toggleInlineMarker('*');

  void _toggleUnderline() => _toggleInlineMarker('++');

  void _toggleHeading(String marker) {
    final text = _controller.text;
    final firstNewline = text.indexOf('\n');
    if (firstNewline == -1) return;

    final sel = _controller.selection;
    final rawOffset = sel.isValid
        ? (sel.isCollapsed ? sel.baseOffset : sel.start)
        : text.length;
    if (rawOffset <= firstNewline) return;

    final workingOffset = rawOffset.clamp(firstNewline + 1, text.length);
    final lineStart = text.lastIndexOf('\n', workingOffset - 1) + 1;
    final lineEndRaw = text.indexOf('\n', workingOffset);
    final lineEnd = lineEndRaw < 0 ? text.length : lineEndRaw;
    final line = text.substring(lineStart, lineEnd);

    if (line.startsWith(_bulletMarker) || _checkboxMarkerPrefix(line) != null) {
      return;
    }

    final String oldMarker;
    if (line.startsWith(_h2Marker)) {
      oldMarker = _h2Marker;
    } else if (line.startsWith(_h1Marker)) {
      oldMarker = _h1Marker;
    } else {
      oldMarker = '';
    }

    final newMarker = oldMarker == marker ? '' : marker;
    final newLine = newMarker + line.substring(oldMarker.length);
    final updated =
        text.substring(0, lineStart) + newLine + text.substring(lineEnd);
    final delta = newMarker.length - oldMarker.length;
    final baseOffset = sel.isValid ? sel.baseOffset : workingOffset;
    final extentOffset = sel.isValid ? sel.extentOffset : workingOffset;
    _replaceSelection(
      updated,
      TextSelection(
        baseOffset: (baseOffset + delta).clamp(0, updated.length),
        extentOffset: (extentOffset + delta).clamp(0, updated.length),
      ),
    );
  }

  void _toggleH1() => _toggleHeading(_h1Marker);

  void _toggleH2() => _toggleHeading(_h2Marker);

  /// Toggle a bullet (`- `) on the current body line.
  /// Bullet and checkbox are mutually exclusive: pressing bullet on a checkbox
  /// line converts it to a bullet, and vice-versa.
  void _toggleBulletAtCursor() {
    final text = _controller.text;
    final firstNewline = text.indexOf('\n');
    final sel = _controller.selection;
    final rawOffset = sel.isValid
        ? (sel.isCollapsed ? sel.baseOffset : sel.start)
        : text.length;

    final String prepared;
    final int workingOffset;
    if (firstNewline == -1) {
      prepared = '$text\n';
      workingOffset = prepared.length;
    } else if (rawOffset <= firstNewline) {
      prepared = text;
      workingOffset = firstNewline + 1;
    } else {
      prepared = text;
      workingOffset = rawOffset.clamp(firstNewline + 1, text.length);
    }

    final lineStart = prepared.lastIndexOf('\n', workingOffset - 1) + 1;
    final lineEndRaw = prepared.indexOf('\n', workingOffset);
    final lineEnd = lineEndRaw < 0 ? prepared.length : lineEndRaw;
    final line = prepared.substring(lineStart, lineEnd);

    final String newLine;
    final int cursorAfter;

    if (line.startsWith(_bulletMarker)) {
      // Remove bullet
      newLine = line.substring(_bulletMarker.length);
      cursorAfter = _cursorAfterMarkerSwap(
        cursor: workingOffset,
        lineStart: lineStart,
        oldMarker: _bulletMarker,
        newMarker: '',
      );
    } else {
      final cbMarker = _checkboxMarkerPrefix(line);
      final oldMarker = cbMarker ?? '';
      // Convert checkbox → bullet, or add bullet to plain line
      newLine = _bulletMarker + line.substring(oldMarker.length);
      cursorAfter = _cursorAfterMarkerSwap(
        cursor: workingOffset,
        lineStart: lineStart,
        oldMarker: oldMarker,
        newMarker: _bulletMarker,
      );
    }

    final newText =
        prepared.substring(0, lineStart) +
        newLine +
        prepared.substring(lineEnd);
    _focusNode.requestFocus();
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: cursorAfter.clamp(0, newText.length),
      ),
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

  void _applyRemoteNoteIfClean(Note note) {
    if (!_initialized) {
      _controller.text = _buildInitial(note);
      _lastSavedTitle = note.title;
      _lastSavedContent = _normalizeCheckedMarkers(note.content);
      _lastAppliedRemoteUpdate = note.updatedAt;
      _initialized = true;
      return;
    }

    final remoteText = _buildInitial(note);
    if (remoteText == _controller.text) {
      _lastSavedTitle = note.title;
      _lastSavedContent = _normalizeCheckedMarkers(note.content);
      _lastAppliedRemoteUpdate = note.updatedAt;
      return;
    }

    if (_isDirty || _focusNode.hasFocus) return;
    if (_lastAppliedRemoteUpdate != null &&
        !note.updatedAt.isAfter(_lastAppliedRemoteUpdate!)) {
      return;
    }

    final cursor = _controller.selection.baseOffset.clamp(0, remoteText.length);
    _controller.value = TextEditingValue(
      text: remoteText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _lastSavedTitle = note.title;
    _lastSavedContent = _normalizeCheckedMarkers(note.content);
    _lastAppliedRemoteUpdate = note.updatedAt;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bodyStyle =
        theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    final bodyFontSize = bodyStyle.fontSize ?? 16.0;
    final asyncNotes = ref.watch(noteListProvider);

    return asyncNotes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notes) {
        try {
          final client = ref.read(supabaseClientProvider);
          _saveWithoutProviderRefresh =
              (id, {String? title, String? content}) => NoteRepository(
                client,
              ).update(id, title: title, content: content);
        } catch (_) {
          _saveWithoutProviderRefresh = null;
        }

        final note = _findNote(notes);
        if (note == null) return const Center(child: Text('Note not found'));

        _applyRemoteNoteIfClean(note);
        _requestTitleFocus();

        return Column(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: bodyStyle,
                inputFormatters: [_NoteListFormatter()],
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontWeight: FontWeight.bold,
                    fontSize: bodyFontSize * 1.3,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: _editorPadding,
                ),
                onChanged: (_) => _scheduleSave(),
              ),
            ),
            _NoteFormatToolbar(
              onBold: _toggleBold,
              onItalic: _toggleItalic,
              onUnderline: _toggleUnderline,
              onH1: _toggleH1,
              onH2: _toggleH2,
              onBullet: _toggleBulletAtCursor,
              onCheckbox: _toggleCheckboxAtCursor,
            ),
            _NoteSyncFooter(
              note: note,
              hasUnsavedEditorChanges: _hasUnsavedEditorChanges,
            ),
          ],
        );
      },
    );
  }
}

class _NoteFormatToolbar extends StatelessWidget {
  const _NoteFormatToolbar({
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onH1,
    required this.onH2,
    required this.onBullet,
    required this.onCheckbox,
  });

  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onH1;
  final VoidCallback onH2;
  final VoidCallback onBullet;
  final VoidCallback onCheckbox;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = BorderSide(
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
    );

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(top: border),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ToolbarTextButton(
                label: 'B',
                tooltip: 'Bold',
                style: const TextStyle(fontWeight: FontWeight.bold),
                onPressed: onBold,
              ),
              _ToolbarTextButton(
                label: 'I',
                tooltip: 'Italic',
                style: const TextStyle(fontStyle: FontStyle.italic),
                onPressed: onItalic,
              ),
              _ToolbarTextButton(
                label: 'U',
                tooltip: 'Underline',
                style: const TextStyle(decoration: TextDecoration.underline),
                onPressed: onUnderline,
              ),
              const SizedBox(width: 4),
              _ToolbarTextButton(
                label: 'H1',
                tooltip: 'Heading 1',
                onPressed: onH1,
              ),
              _ToolbarTextButton(
                label: 'H2',
                tooltip: 'Heading 2',
                onPressed: onH2,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.format_list_bulleted),
                iconSize: 20,
                tooltip: 'Toggle bullet',
                onPressed: onBullet,
              ),
              IconButton(
                icon: const Icon(Icons.check_box_outlined),
                iconSize: 20,
                tooltip: 'Toggle checkbox',
                onPressed: onCheckbox,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarTextButton extends StatelessWidget {
  const _ToolbarTextButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.style,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed,
        child: Text(label, style: style),
      ),
    );
  }
}

class _NoteSyncFooter extends StatelessWidget {
  const _NoteSyncFooter({
    required this.note,
    required this.hasUnsavedEditorChanges,
  });

  final Note note;
  final bool hasUnsavedEditorChanges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _syncText(),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ),
    );
  }

  String _syncText() {
    if (hasUnsavedEditorChanges) return 'Editing...';
    if (note.syncStatus == 'pending') return 'Pending sync';
    final lastSyncedAt = note.lastSyncedAt;
    if (lastSyncedAt == null) return 'Not synced yet';
    return 'Synced ${_formatDateTime(lastSyncedAt.toLocal())}';
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} '
        '$hour12:$minute $suffix';
  }
}

/// Renders the title (first line) in bold at 1.3× size.
/// Checkbox markers (☐ / ☑) are replaced by WidgetSpan inline icons so that
/// checked and unchecked states always occupy identical widths — no text shift.
/// The space character after each marker glyph becomes a fixed-width SizedBox.
class _NoteController extends TextEditingController {
  _NoteController({required this.onToggleMarker});

  final void Function(int textOffset, TextSelection? preserve) onToggleMarker;

  static const double _iconSize = 18.0;
  static const double _iconGap = 6.0;

  /// When set, any incoming value change that only moves the selection (text
  /// unchanged) is silently overridden with this selection instead. Released
  /// after the frame following a toggle, preventing the TextField's own
  /// TapGestureRecognizer from moving the cursor regardless of firing order.
  TextSelection? _selectionLock;

  @override
  set value(TextEditingValue newValue) {
    final lock = _selectionLock;
    if (lock != null && newValue.text == value.text) {
      super.value = newValue.copyWith(selection: lock);
    } else {
      super.value = newValue;
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base =
        style ?? Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    final cs = Theme.of(context).colorScheme;
    final titleStyle = base.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: (base.fontSize ?? 16.0) * 1.3,
    );
    final h1Style = base.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: (base.fontSize ?? 16.0) * 1.25,
    );
    final h2Style = base.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: (base.fontSize ?? 16.0) * 1.12,
    );

    final text = this.text;
    final newlineIndex = text.indexOf('\n');

    if (newlineIndex == -1) {
      return TextSpan(text: text, style: titleStyle);
    }

    final children = <InlineSpan>[
      TextSpan(text: text.substring(0, newlineIndex), style: titleStyle),
      const TextSpan(text: '\n'),
    ];

    // Captured at pointer-down (before text-field gesture recognizer fires)
    // so the selection doesn't drift when the user clicks a checkbox icon.
    TextSelection? pointerDownSelection;

    var absoluteOffset = newlineIndex + 1;
    final lines = text.substring(newlineIndex + 1).split('\n');

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) children.add(const TextSpan(text: '\n'));

      final line = lines[i];
      final lineStart = absoluteOffset;
      final cbMarker = _checkboxMarkerPrefix(line);
      final isBullet = cbMarker == null && line.startsWith(_bulletMarker);

      if (cbMarker != null) {
        final isChecked = _isCheckedMarker(cbMarker);

        // WidgetSpan for the glyph character (☐ or ☑).
        // Fixed iconSize width regardless of which glyph — no text shift on toggle.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                pointerDownSelection = value.selection.isValid
                    ? value.selection
                    : null;
              },
              child: GestureDetector(
                key: ValueKey('note-checkbox-icon-$lineStart'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onToggleMarker(lineStart, pointerDownSelection),
                child: MouseRegion(
                  cursor: SystemMouseCursors.basic,
                  child: Icon(
                    isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                    size: _iconSize,
                    color: isChecked
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        );

        // WidgetSpan for the space after the glyph — fixed gap width.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: _iconGap, height: _iconSize),
          ),
        );

        if (line.length > cbMarker.length) {
          children.addAll(
            _markdownInlineSpans(line.substring(cbMarker.length), base),
          );
        }
      } else if (isBullet) {
        // WidgetSpan for '-' — renders as a small filled circle, same width as
        // the checkbox icon so mixed lists stay aligned.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: SizedBox(
              width: _iconSize,
              height: _iconSize,
              child: Center(
                child: Icon(
                  Icons.circle,
                  size: 7.0,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        );

        // WidgetSpan for the space after '-' — same gap as checkboxes.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: _iconGap, height: _iconSize),
          ),
        );

        if (line.length > _bulletMarker.length) {
          children.addAll(
            _markdownInlineSpans(line.substring(_bulletMarker.length), base),
          );
        }
      } else if (line.isNotEmpty) {
        final TextStyle lineStyle;
        final String content;
        if (line.startsWith(_h2Marker)) {
          lineStyle = h2Style;
          content = line.substring(_h2Marker.length);
        } else if (line.startsWith(_h1Marker)) {
          lineStyle = h1Style;
          content = line.substring(_h1Marker.length);
        } else {
          lineStyle = base;
          content = line;
        }
        children.addAll(_markdownInlineSpans(content, lineStyle));
      }

      absoluteOffset += line.length + 1;
    }

    return TextSpan(style: base, children: children);
  }
}

List<InlineSpan> _markdownInlineSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: style));
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    if (text.startsWith('**', i)) {
      final end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(i + 2, end),
            style: style.copyWith(fontWeight: FontWeight.bold),
          ),
        );
        i = end + 2;
        continue;
      }
    }

    if (text.startsWith('++', i)) {
      final end = text.indexOf('++', i + 2);
      if (end > i + 2) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(i + 2, end),
            style: style.copyWith(decoration: TextDecoration.underline),
          ),
        );
        i = end + 2;
        continue;
      }
    }

    if (text.startsWith('*', i) && !text.startsWith('**', i)) {
      final end = text.indexOf('*', i + 1);
      if (end > i + 1) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(i + 1, end),
            style: style.copyWith(fontStyle: FontStyle.italic),
          ),
        );
        i = end + 1;
        continue;
      }
    }

    buffer.write(text[i]);
    i++;
  }

  flush();
  return spans;
}

/// When the user presses Enter at the end of a list line, continue the list
/// on the next line. On an empty list line, terminate the list instead.
class _NoteListFormatter extends TextInputFormatter {
  static const _hyphen = '- ';

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

    final marker = _continuationMarker(prevLine);
    if (marker == null) return newValue;

    if (_isEmptyListLine(prevLine, marker)) {
      final newText =
          '${newValue.text.substring(0, prevLineStart)}\n${newValue.text.substring(cursor)}';
      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: prevLineStart + 1),
      );
    }

    final after = newValue.text.substring(cursor);
    if (after.startsWith(marker)) return newValue;
    final updated = newValue.text.substring(0, cursor) + marker + after;
    return TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: cursor + marker.length),
    );
  }

  String? _continuationMarker(String line) {
    if (_checkboxMarkerPrefix(line) != null) return _uncheckedMarker;
    if (line.startsWith(_hyphen)) return _hyphen;
    if (line.startsWith('-') && line.length > 1) return _hyphen;
    return null;
  }

  bool _isEmptyListLine(String line, String marker) {
    if (marker == _hyphen) return line == '-' || line == _hyphen;
    return _checkboxMarkerPrefix(line) != null && line.length == marker.length;
  }
}
