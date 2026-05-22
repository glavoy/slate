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

String? _markerPrefix(String line) {
  if (line.startsWith(_uncheckedMarker)) return _uncheckedMarker;
  if (line.startsWith(_checkedMarker)) return _checkedMarker;
  if (line.startsWith(_legacyCheckedMarker)) return _legacyCheckedMarker;
  return null;
}

bool _isCheckedMarker(String marker) =>
    marker == _checkedMarker || marker == _legacyCheckedMarker;

String _normalizeCheckedMarkers(String text) =>
    text.replaceAll(_legacyCheckedMarker, _checkedMarker);

/// Allows a parent AppBar to invoke actions inside the pane without a GlobalKey.
/// The pane registers its callbacks on init and unregisters on dispose.
/// A generation counter prevents a newly registered pane from being accidentally
/// unregistered by the dispose of an outgoing pane when the note selection changes.
class NoteEditorController {
  int _generation = 0;
  VoidCallback? _toggleCheckboxFn;
  VoidCallback? _focusTitleFn;
  Future<void> Function(BuildContext)? _deleteFn;

  int _register({
    required VoidCallback toggleCheckbox,
    required VoidCallback focusTitle,
    required Future<void> Function(BuildContext) delete,
  }) {
    _toggleCheckboxFn = toggleCheckbox;
    _focusTitleFn = focusTitle;
    _deleteFn = delete;
    return ++_generation;
  }

  void _unregister(int gen) {
    if (_generation == gen) {
      _toggleCheckboxFn = null;
      _focusTitleFn = null;
      _deleteFn = null;
    }
  }

  void toggleCheckbox() => _toggleCheckboxFn?.call();
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
      onToggleMarker: (offset) => _toggleMarkerAt(
        offset,
        preserveSelection: _controller.selection.isValid
            ? _controller.selection
            : null,
      ),
    );
    _focusNode.addListener(_handleFocusChanged);
    if (widget.controller != null) {
      _controllerGeneration = widget.controller!._register(
        toggleCheckbox: _toggleCheckboxAtCursor,
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
    final marker = _markerPrefix(line);

    final String replacement;
    final int cursorAfter;
    if (marker == null) {
      replacement = _uncheckedMarker + line;
      cursorAfter = lineStart + _uncheckedMarker.length;
    } else if (marker == _uncheckedMarker) {
      replacement = _checkedMarker + line.substring(marker.length);
      cursorAfter = _cursorAfterMarkerSwap(
        cursor: workingOffset,
        lineStart: lineStart,
        oldMarker: marker,
        newMarker: _checkedMarker,
      );
    } else {
      replacement = _uncheckedMarker + line.substring(marker.length);
      cursorAfter = _cursorAfterMarkerSwap(
        cursor: workingOffset,
        lineStart: lineStart,
        oldMarker: marker,
        newMarker: _uncheckedMarker,
      );
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
    _controller.value = TextEditingValue(text: newText, selection: newSelection);
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
    final bodyStyle = theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
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

  final void Function(int textOffset) onToggleMarker;

  static const double _iconSize = 18.0;
  static const double _iconGap = 6.0;

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

    final text = this.text;
    final newlineIndex = text.indexOf('\n');

    if (newlineIndex == -1) {
      return TextSpan(text: text, style: titleStyle);
    }

    final children = <InlineSpan>[
      TextSpan(text: text.substring(0, newlineIndex), style: titleStyle),
      const TextSpan(text: '\n'),
    ];

    var absoluteOffset = newlineIndex + 1;
    final lines = text.substring(newlineIndex + 1).split('\n');

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) children.add(const TextSpan(text: '\n'));

      final line = lines[i];
      final lineStart = absoluteOffset;
      final marker = _markerPrefix(line);

      if (marker != null) {
        final isChecked = _isCheckedMarker(marker);

        // WidgetSpan for the glyph character (☐ or ☑).
        // Fixed iconSize width regardless of which glyph — no text shift on toggle.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              key: ValueKey('note-checkbox-icon-$lineStart'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggleMarker(lineStart),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
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
        );

        // WidgetSpan for the space after the glyph — fixed gap width.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: _iconGap, height: _iconSize),
          ),
        );

        if (line.length > marker.length) {
          children.add(TextSpan(text: line.substring(marker.length)));
        }
      } else if (line.isNotEmpty) {
        children.add(TextSpan(text: line));
      }

      absoluteOffset += line.length + 1;
    }

    return TextSpan(style: base, children: children);
  }
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
    if (_markerPrefix(line) != null) return _uncheckedMarker;
    if (line.startsWith(_hyphen)) return _hyphen;
    if (line.startsWith('-') && line.length > 1) return _hyphen;
    return null;
  }

  bool _isEmptyListLine(String line, String marker) {
    if (marker == _hyphen) return line == '-' || line == _hyphen;
    return _markerPrefix(line) != null && line.length == marker.length;
  }
}
