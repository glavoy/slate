import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';
import '../providers/supabase_provider.dart';
import '../repositories/note_repository.dart';

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
  static const _uncheckedCheckbox = '☐ ';
  static const _checkedCheckbox = '☒ ';
  static const _legacyCheckedCheckbox = '☑ ';

  @override
  void initState() {
    super.initState();
    _controller = _NoteController();
    _focusNode.addListener(_handleFocusChanged);
    if (widget.controller != null) {
      _controllerGeneration = widget.controller!._register(
        toggleCheckbox: _toggleCheckbox,
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
    if (note.title.isEmpty && note.content.isEmpty) return '';
    if (note.title.isEmpty) return note.content;
    if (note.content.isEmpty) return note.title;
    return '${note.title}\n${note.content}';
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

  void _toggleCheckbox() {
    _toggleCheckboxAtCursor(restoreFocus: true);
  }

  int _cursorForMarkerToggle({
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

  void _toggleCheckboxAtCursor({
    required bool restoreFocus,
    bool onlyWhenCursorInsideMarker = false,
  }) {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final cursor = sel.isCollapsed ? sel.baseOffset : sel.start;
    _toggleCheckboxAtOffset(
      offset: cursor,
      selectionAfterToggle: null,
      restoreFocus: restoreFocus,
      onlyWhenOffsetInsideMarker: onlyWhenCursorInsideMarker,
    );
  }

  void _toggleCheckboxAtOffset({
    required int offset,
    required TextSelection? selectionAfterToggle,
    required bool restoreFocus,
    bool onlyWhenOffsetInsideMarker = false,
  }) {
    final text = _controller.text;
    final cursor = offset;

    // Only apply to body lines (after the title's first \n)
    final firstNewline = text.indexOf('\n');
    if (firstNewline == -1 || cursor <= firstNewline) return;

    final lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
    final lineEndRaw = text.indexOf('\n', cursor);
    final lineEnd = lineEndRaw < 0 ? text.length : lineEndRaw;
    final line = text.substring(lineStart, lineEnd);

    final existingMarker = _existingCheckboxMarker(line);
    if (onlyWhenOffsetInsideMarker && existingMarker == null) return;
    if (onlyWhenOffsetInsideMarker &&
        cursor > lineStart + existingMarker!.length) {
      return;
    }

    final String newText;
    final int fallbackCursor;

    if (line.startsWith(_uncheckedCheckbox)) {
      newText =
          text.substring(0, lineStart) +
          _checkedCheckbox +
          line.substring(_uncheckedCheckbox.length) +
          text.substring(lineEnd);
      fallbackCursor = _cursorForMarkerToggle(
        cursor: cursor,
        lineStart: lineStart,
        oldMarker: _uncheckedCheckbox,
        newMarker: _checkedCheckbox,
      );
    } else if (line.startsWith(_checkedCheckbox) ||
        line.startsWith(_legacyCheckedCheckbox)) {
      final checkedMarker = line.startsWith(_checkedCheckbox)
          ? _checkedCheckbox
          : _legacyCheckedCheckbox;
      newText =
          text.substring(0, lineStart) +
          _uncheckedCheckbox +
          line.substring(checkedMarker.length) +
          text.substring(lineEnd);
      fallbackCursor = _cursorForMarkerToggle(
        cursor: cursor,
        lineStart: lineStart,
        oldMarker: checkedMarker,
        newMarker: _uncheckedCheckbox,
      );
    } else {
      newText =
          text.substring(0, lineStart) +
          _uncheckedCheckbox +
          text.substring(lineStart);
      fallbackCursor = lineStart + _uncheckedCheckbox.length;
    }

    final newSelection =
        selectionAfterToggle?.copyWith(
          baseOffset: selectionAfterToggle.baseOffset.clamp(0, newText.length),
          extentOffset: selectionAfterToggle.extentOffset.clamp(
            0,
            newText.length,
          ),
        ) ??
        TextSelection.collapsed(
          offset: fallbackCursor.clamp(0, newText.length),
        );
    _controller.value = TextEditingValue(
      text: newText,
      selection: newSelection,
    );
    if (restoreFocus) {
      _restoreEditorFocus(newSelection.extentOffset);
    }
    _scheduleSave();
  }

  String? _existingCheckboxMarker(String line) {
    if (line.startsWith(_uncheckedCheckbox)) return _uncheckedCheckbox;
    if (line.startsWith(_checkedCheckbox)) return _checkedCheckbox;
    if (line.startsWith(_legacyCheckedCheckbox)) return _legacyCheckedCheckbox;
    return null;
  }

  List<_CheckboxHotspot> _buildCheckboxHotspots({
    required BuildContext context,
    required TextStyle baseStyle,
    required double maxWidth,
  }) {
    final text = _controller.text;
    final newlineIndex = text.indexOf('\n');
    if (newlineIndex == -1) return const [];

    final contentWidth = maxWidth - _editorPadding.horizontal;
    if (contentWidth <= 0) return const [];

    final painter = TextPainter(
      text: _controller.buildTextSpan(
        context: context,
        style: baseStyle,
        withComposing: true,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: contentWidth);

    final body = text.substring(newlineIndex);
    final bodyLines = body.split('\n');
    final hotspots = <_CheckboxHotspot>[];
    var absoluteOffset = newlineIndex;

    for (var i = 0; i < bodyLines.length; i++) {
      final line = bodyLines[i];
      if (i > 0) {
        absoluteOffset += 1;
      }
      final lineStart = absoluteOffset;
      final marker = _existingCheckboxMarker(line);
      if (marker != null) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(
            baseOffset: lineStart,
            extentOffset: lineStart + marker.length,
          ),
        );
        for (final box in boxes) {
          hotspots.add(
            _CheckboxHotspot(
              textOffset: lineStart,
              left: _editorPadding.left + box.left,
              top: _editorPadding.top + box.top,
              width: (box.right - box.left).abs(),
              height: (box.bottom - box.top).abs(),
            ),
          );
        }
      }
      absoluteOffset += line.length;
    }

    return hotspots;
  }

  void _toggleCheckboxFromOverlay(int offset) {
    final selection = _controller.selection;
    _toggleCheckboxAtOffset(
      offset: offset,
      selectionAfterToggle: selection.isValid ? selection : null,
      restoreFocus: false,
    );
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _restoreEditorFocus(int cursor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection.collapsed(
        offset: cursor.clamp(0, _controller.text.length),
      );
    });
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
      _lastSavedContent = note.content;
      _lastAppliedRemoteUpdate = note.updatedAt;
      _initialized = true;
      return;
    }

    final remoteText = _buildInitial(note);
    if (remoteText == _controller.text) {
      _lastSavedTitle = note.title;
      _lastSavedContent = note.content;
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
    _lastSavedContent = note.content;
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final hotspots = _buildCheckboxHotspots(
              context: context,
              baseStyle: bodyStyle,
              maxWidth: constraints.maxWidth,
            );
            return Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      TextField(
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
                      ...hotspots.map(
                        (hotspot) => Positioned(
                          left: hotspot.left,
                          top: hotspot.top,
                          width: hotspot.width,
                          height: hotspot.height,
                          child: MouseRegion(
                            key: ValueKey(
                              'note-checkbox-hotspot-${hotspot.textOffset}',
                            ),
                            cursor: SystemMouseCursors.basic,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  _toggleCheckboxFromOverlay(hotspot.textOffset),
                            ),
                          ),
                        ),
                      ),
                    ],
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
      },
    );
  }
}

class _CheckboxHotspot {
  const _CheckboxHotspot({
    required this.textOffset,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int textOffset;
  final double left;
  final double top;
  final double width;
  final double height;
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
    final months = [
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

// Renders the first line (title) bold at 1.3× size; body lines use the base style.
class _NoteController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base =
        style ?? Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
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

class _NoteListFormatter extends TextInputFormatter {
  static const _uncheckedCheckbox = '☐ ';
  static const _checkedCheckbox = '☒ ';
  static const _legacyCheckedCheckbox = '☑ ';
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
    if (line.startsWith(_uncheckedCheckbox) ||
        line.startsWith(_checkedCheckbox) ||
        line.startsWith(_legacyCheckedCheckbox)) {
      return _uncheckedCheckbox;
    }
    if (line.startsWith(_hyphen)) return _hyphen;
    if (line.startsWith('-') && line.length > 1) return _hyphen;
    return null;
  }

  bool _isEmptyListLine(String line, String marker) {
    if (marker == _hyphen) {
      return line == '-' || line == _hyphen;
    }
    return line == marker;
  }
}
