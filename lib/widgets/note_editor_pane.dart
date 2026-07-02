import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';
import '../providers/supabase_provider.dart';
import '../repositories/note_repository.dart';

/// Plain-text preview for a note body. Supports both the new Quill Delta JSON
/// format and legacy plain-text content (older notes from before the editor
/// rewrite — those render as-is).
String noteBodyPreview(String content) {
  if (content.isEmpty) return '';
  try {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      final buf = StringBuffer();
      for (final op in decoded) {
        if (op is Map && op['insert'] is String) {
          buf.write(op['insert'] as String);
        }
      }
      return buf.toString();
    }
  } catch (_) {
    /* fall through to legacy */
  }
  return content;
}

Document _documentFromContent(String content) {
  if (content.trim().isEmpty) return Document();
  try {
    final decoded = jsonDecode(content);
    if (decoded is List) return Document.fromJson(decoded);
  } catch (_) {
    /* legacy plain text */
  }
  // Legacy notes seed as a single plain-text insert so they at least show up.
  return Document()..insert(0, content);
}

/// Deletes a non-collapsed selection directly through the Quill controller
/// instead of flutter_quill's plain-text diff pipeline
/// (`TextEditingValue.replaced` → `getDiff` → `replaceTextWithEmbeds`), which
/// can leave the caret past the end of the document after a full-document
/// delete and desync the IME state — after which delete/format keystrokes
/// silently stop working. Registered above the editor so flutter_quill's
/// `Action.overridable` wrappers defer to it; collapsed-cursor deletes are
/// delegated back to the quill default via [callingAction] (preserving its
/// backspace style-memory behavior).
class SelectionSafeDeleteAction<T extends DirectionalTextEditingIntent>
    extends Action<T> {
  SelectionSafeDeleteAction(this.controller);

  final QuillController controller;

  @override
  Object? invoke(T intent) {
    final selection = controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      controller.replaceText(
        selection.start,
        selection.end - selection.start,
        '',
        TextSelection.collapsed(offset: selection.start),
      );
      return null;
    }
    return callingAction?.invoke(intent);
  }

  @override
  bool get isActionEnabled => true;
}

/// Bridge so the AppBar can invoke pane-level actions (focus title, confirm
/// delete) without holding a GlobalKey. A generation counter prevents a newly
/// registered pane from being accidentally unregistered by an outgoing pane.
class NoteEditorController {
  int _generation = 0;
  VoidCallback? _focusTitleFn;
  Future<void> Function(BuildContext)? _deleteFn;

  int _register({
    required VoidCallback focusTitle,
    required Future<void> Function(BuildContext) delete,
  }) {
    _focusTitleFn = focusTitle;
    _deleteFn = delete;
    return ++_generation;
  }

  void _unregister(int gen) {
    if (_generation == gen) {
      _focusTitleFn = null;
      _deleteFn = null;
    }
  }

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
  late final QuillController _quill;
  late final TextEditingController _titleController;
  final _editorFocusNode = FocusNode();
  final _titleFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;

  late final Map<Type, Action<Intent>> _deleteOverrides;

  String _lastSavedTitle = '';
  String _lastSavedContent = '';
  bool _initialized = false;
  bool _applyingRemote = false;
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
    _quill = QuillController.basic();
    _deleteOverrides = {
      DeleteCharacterIntent: SelectionSafeDeleteAction<DeleteCharacterIntent>(
        _quill,
      ),
      DeleteToNextWordBoundaryIntent:
          SelectionSafeDeleteAction<DeleteToNextWordBoundaryIntent>(_quill),
      DeleteToLineBreakIntent:
          SelectionSafeDeleteAction<DeleteToLineBreakIntent>(_quill),
    };
    _titleController = TextEditingController();
    _titleController.addListener(_onTitleChanged);
    _quill.addListener(_onQuillChanged);
    _editorFocusNode.addListener(_handleFocusChanged);
    _titleFocusNode.addListener(_handleFocusChanged);
    // Capture a repository-backed save closure once, up front, so the dispose
    // flush can always persist the final edit even when the widget tree (and
    // its providers) are being torn down.
    final client = ref.read(supabaseClientProvider);
    _saveWithoutProviderRefresh = (id, {String? title, String? content}) =>
        NoteRepository(client).update(id, title: title, content: content);
    if (widget.controller != null) {
      _controllerGeneration = widget.controller!._register(
        focusTitle: _focusTitle,
        delete: _confirmDelete,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flushIfDirty(updateUi: false, refreshProvider: false);
    _titleController.removeListener(_onTitleChanged);
    _quill.removeListener(_onQuillChanged);
    _editorFocusNode.removeListener(_handleFocusChanged);
    _titleFocusNode.removeListener(_handleFocusChanged);
    widget.controller?._unregister(_controllerGeneration);
    _quill.dispose();
    _titleController.dispose();
    _editorFocusNode.dispose();
    _titleFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _serializedContent =>
      jsonEncode(_quill.document.toDelta().toJson());

  bool get _isDirty =>
      _initialized &&
      (_titleController.text != _lastSavedTitle ||
          _serializedContent != _lastSavedContent);

  bool get _hasFocus => _editorFocusNode.hasFocus || _titleFocusNode.hasFocus;

  void _onTitleChanged() {
    if (_applyingRemote) return;
    _scheduleSave();
  }

  void _onQuillChanged() {
    if (!_initialized || _applyingRemote) return;
    // QuillController fires on selection changes too; gate on dirty.
    if (_isDirty) _scheduleSave();
  }

  void _handleFocusChanged() {
    if (!_hasFocus && mounted) setState(() {});
  }

  void _scheduleSave() {
    if (!_initialized) return;
    if (!_hasUnsavedEditorChanges) {
      setState(() => _hasUnsavedEditorChanges = true);
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flushIfDirty);
  }

  void _flushIfDirty({bool updateUi = true, bool refreshProvider = true}) {
    if (!_initialized) return;
    final title = _titleController.text;
    final content = _serializedContent;
    if (title == _lastSavedTitle && content == _lastSavedContent) {
      if (_hasUnsavedEditorChanges) {
        if (updateUi && mounted) {
          setState(() => _hasUnsavedEditorChanges = false);
        } else {
          _hasUnsavedEditorChanges = false;
        }
      }
      return;
    }
    _lastSavedTitle = title;
    _lastSavedContent = content;
    if (updateUi && mounted) {
      setState(() => _hasUnsavedEditorChanges = false);
    } else {
      _hasUnsavedEditorChanges = false;
    }
    if (refreshProvider) {
      ref
          .read(noteListProvider.notifier)
          .edit(widget.noteId, title: title, content: content);
    } else {
      _saveWithoutProviderRefresh?.call(
        widget.noteId,
        title: title,
        content: content,
      );
    }
  }

  void _requestTitleFocus() {
    if (!widget.autoFocusTitle || _autoFocusRequested) return;
    _autoFocusRequested = true;
    _focusTitle();
  }

  void _focusTitle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocusNode.requestFocus();
      _titleController.selection = TextSelection.collapsed(
        offset: _titleController.text.length,
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
      _titleController.text = note.title;
      _quill.document = _documentFromContent(note.content);
      _lastSavedTitle = note.title;
      _lastSavedContent = _serializedContent;
      _lastAppliedRemoteUpdate = note.updatedAt;
      _initialized = true;
      return;
    }

    // While the user is editing (focused) or has unsaved edits, never touch the
    // saved baseline or the document. Doing so on a rebuild that fires mid-edit
    // (e.g. after a single delete/paste) wrongly marks the live content as saved,
    // and the pending debounce then skips persisting it.
    if (_isDirty || _hasFocus) return;

    // Editor is clean: the persisted note is the source of truth.
    if (note.title == _lastSavedTitle && note.content == _lastSavedContent) {
      _lastAppliedRemoteUpdate = note.updatedAt;
      return;
    }
    if (_lastAppliedRemoteUpdate != null &&
        !note.updatedAt.isAfter(_lastAppliedRemoteUpdate!)) {
      return;
    }

    // Reseeding replaces the document, which resets the controller selection
    // to offset 0. Preserve the caret (clamped to the new length) so a remote
    // refresh doesn't yank the cursor away, and suppress the change listeners
    // so applying remote content is never mistaken for a local edit.
    _applyingRemote = true;
    try {
      final previousOffset = _quill.selection.baseOffset;
      _titleController.text = note.title;
      _quill.document = _documentFromContent(note.content);
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
    _lastSavedTitle = note.title;
    _lastSavedContent = _serializedContent;
    _lastAppliedRemoteUpdate = note.updatedAt;
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

        _applyRemoteNoteIfClean(note);
        _requestTitleFocus();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _editorFocusNode.requestFocus(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              // flutter_quill's keyboard actions are Action.overridable and
              // look up the tree for same-typed intents, so this hands every
              // delete path (Shortcuts and macOS performSelector) to
              // SelectionSafeDeleteAction.
              child: Actions(
                actions: _deleteOverrides,
                child: QuillEditor(
                  controller: _quill,
                  focusNode: _editorFocusNode,
                  scrollController: _scrollController,
                  config: QuillEditorConfig(
                    placeholder: 'Start writing…',
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    expands: true,
                    scrollable: true,
                    autoFocus: false,
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
                  ),
                ),
              ),
            ),
            _NoteFormatToolbar(
              controller: _quill,
              editorFocusNode: _editorFocusNode,
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

// ── Toolbar ──────────────────────────────────────────────────────────────────

class _NoteFormatToolbar extends StatelessWidget {
  const _NoteFormatToolbar({
    required this.controller,
    required this.editorFocusNode,
  });

  final QuillController controller;
  final FocusNode editorFocusNode;

  /// Run a format action and immediately hand focus back to the editor so the
  /// caret stays visible and the user can keep typing. We re-request focus
  /// synchronously AND after the current frame to win against any focus changes
  /// Flutter dispatches during the button's tap pipeline (on mobile this also
  /// keeps the soft keyboard up).
  void _withFocus(VoidCallback action) {
    action();
    editorFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editorFocusNode.canRequestFocus) editorFocusNode.requestFocus();
    });
  }

  void _toggleInline(Attribute attr) {
    final style = controller.getSelectionStyle();
    final isActive = style.attributes.containsKey(attr.key);
    controller.formatSelection(isActive ? Attribute.clone(attr, null) : attr);
  }

  void _toggleBlock(Attribute attr) {
    final style = controller.getSelectionStyle();
    final current = style.attributes[attr.key];
    if (current != null && current.value == attr.value) {
      controller.formatSelection(Attribute.clone(attr, null));
    } else {
      controller.formatSelection(attr);
    }
  }

  /// Checkbox shares the `list` attribute with bullet/numbered but has two "on"
  /// values (checked + unchecked). Treat either as active so a single tap on a
  /// checked line removes the list instead of just unchecking it.
  void _toggleCheckbox() {
    final current = controller
        .getSelectionStyle()
        .attributes[Attribute.list.key];
    final isCheckbox =
        current?.value == Attribute.unchecked.value ||
        current?.value == Attribute.checked.value;
    controller.formatSelection(
      isCheckbox
          ? Attribute.clone(Attribute.unchecked, null)
          : Attribute.unchecked,
    );
  }

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
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final style = controller.getSelectionStyle();
            final attrs = style.attributes;
            final isBold = attrs.containsKey(Attribute.bold.key);
            final isItalic = attrs.containsKey(Attribute.italic.key);
            final isUnderline = attrs.containsKey(Attribute.underline.key);
            final isBullet =
                attrs[Attribute.list.key]?.value == Attribute.ul.value;
            final isNumbered =
                attrs[Attribute.list.key]?.value == Attribute.ol.value;
            final isCheckbox =
                attrs[Attribute.list.key]?.value == Attribute.unchecked.value ||
                attrs[Attribute.list.key]?.value == Attribute.checked.value;
            final headerLevel = attrs[Attribute.header.key]?.value;
            final isLarge = headerLevel == 1 || headerLevel == 2;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToggleTextButton(
                    label: 'B',
                    tooltip: 'Bold',
                    active: isBold,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    onPressed: () =>
                        _withFocus(() => _toggleInline(Attribute.bold)),
                  ),
                  _ToggleTextButton(
                    label: 'I',
                    tooltip: 'Italic',
                    active: isItalic,
                    textStyle: const TextStyle(fontStyle: FontStyle.italic),
                    onPressed: () =>
                        _withFocus(() => _toggleInline(Attribute.italic)),
                  ),
                  _ToggleTextButton(
                    label: 'U',
                    tooltip: 'Underline',
                    active: isUnderline,
                    textStyle: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                    onPressed: () =>
                        _withFocus(() => _toggleInline(Attribute.underline)),
                  ),
                  const SizedBox(width: 8),
                  _ToggleTextButton(
                    label: 'A−',
                    tooltip: 'Normal text',
                    active: !isLarge,
                    onPressed: () => _withFocus(
                      () => controller.formatSelection(Attribute.header),
                    ),
                  ),
                  _ToggleTextButton(
                    label: 'A+',
                    tooltip: 'Large text',
                    active: isLarge,
                    onPressed: () => _withFocus(
                      () => controller.formatSelection(Attribute.h2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ToggleIconButton(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Bullet list',
                    active: isBullet,
                    onPressed: () =>
                        _withFocus(() => _toggleBlock(Attribute.ul)),
                  ),
                  _ToggleIconButton(
                    icon: Icons.format_list_numbered,
                    tooltip: 'Numbered list',
                    active: isNumbered,
                    onPressed: () =>
                        _withFocus(() => _toggleBlock(Attribute.ol)),
                  ),
                  _ToggleIconButton(
                    icon: Icons.check_box_outlined,
                    tooltip: 'Checkbox',
                    active: isCheckbox,
                    onPressed: () => _withFocus(_toggleCheckbox),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ToggleTextButton extends StatelessWidget {
  const _ToggleTextButton({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.textStyle,
  });

  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: active ? cs.secondaryContainer : null,
          foregroundColor: active ? cs.onSecondaryContainer : cs.onSurface,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed,
        child: Text(label, style: textStyle),
      ),
    );
  }
}

class _ToggleIconButton extends StatelessWidget {
  const _ToggleIconButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      iconSize: 20,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: active ? cs.secondaryContainer : null,
        foregroundColor: active ? cs.onSecondaryContainer : cs.onSurface,
      ),
      onPressed: onPressed,
    );
  }
}

// ── Sync footer ──────────────────────────────────────────────────────────────

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
