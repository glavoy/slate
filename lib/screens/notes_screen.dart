import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';
import '../widgets/note_editor_pane.dart';
import 'note_editor_screen.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();
  final _editorController = NoteEditorController();
  String _searchQuery = '';
  String? _selectedNoteId;
  bool _autoFocusTitle = false;
  bool _isWide = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Clear selection when the selected note no longer exists (e.g. deleted on
  // another device via realtime).
  void _clearSelectionIfGone(List<Note> notes) {
    if (_selectedNoteId != null &&
        notes.every((n) => n.id != _selectedNoteId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedNoteId = null);
      });
    }
  }

  List<Note> _filtered(List<Note> notes) {
    if (_searchQuery.isEmpty) return notes;
    final q = _searchQuery.toLowerCase();
    return notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(q) ||
              n.content.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _createNote(BuildContext context, bool isWide) async {
    final note = await ref.read(noteListProvider.notifier).create();
    if (!context.mounted) return;
    if (isWide) {
      setState(() {
        _selectedNoteId = note.id;
        _autoFocusTitle = true;
      });
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              NoteEditorScreen(noteId: note.id, autoFocusTitle: true),
        ),
      );
    }
  }

  void _selectNote(BuildContext context, Note note, bool isWide) {
    if (isWide) {
      setState(() {
        _selectedNoteId = note.id;
        _autoFocusTitle = false;
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: note.id)),
      );
    }
  }

  Future<void> _deleteNoteWithUndo(BuildContext context, Note note) async {
    await ref.read(noteListProvider.notifier).delete(note.id);
    if (!context.mounted) return;
    final theme = Theme.of(context);

    if (_selectedNoteId == note.id) {
      setState(() {
        _selectedNoteId = null;
        _autoFocusTitle = false;
      });
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            const Expanded(child: Text('Note moved to trash')),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.inversePrimary,
              ),
              onPressed: () {
                messenger.hideCurrentSnackBar();
                ref.read(deletedNoteListProvider.notifier).restore(note.id);
              },
              child: const Text('Undo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteList(
    BuildContext context,
    List<Note> notes,
    bool isWide,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final filtered = _filtered(notes);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search notes…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                  ),
                ),
              ),
              if (isWide)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New note',
                  onPressed: () => _createNote(context, true),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty ? 'No notes yet' : 'No matching notes',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final note = filtered[i];
                    return _NoteListTile(
                      note: note,
                      isSelected: isWide && note.id == _selectedNoteId,
                      onTap: () => _selectNote(context, note, isWide),
                      onPin: () => ref
                          .read(noteListProvider.notifier)
                          .pin(note.id, value: !note.pinned),
                      onDelete: () => _deleteNoteWithUndo(context, note),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final asyncNotes = ref.watch(noteListProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text(
          'Notes',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            iconSize: 20,
            tooltip: 'Trash',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const _TrashScreen())),
          ),
          if (_selectedNoteId != null)
            IconButton(
              icon: const Icon(Icons.format_list_bulleted),
              iconSize: 20,
              tooltip: 'Toggle bullet',
              onPressed: _editorController.toggleBullet,
            ),
        ],
      ),
      floatingActionButton: _isWide
          ? null
          : FloatingActionButton(
              heroTag: 'fab_notes',
              onPressed: () => _createNote(context, false),
              child: const Icon(Icons.add),
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          if (isWide != _isWide) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isWide = isWide);
            });
          }

          return asyncNotes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (notes) {
              _clearSelectionIfGone(notes);
              if (isWide) {
                return Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: _buildNoteList(context, notes, true, theme, cs),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selectedNoteId != null
                          ? NoteEditorPane(
                              key: ValueKey(_selectedNoteId),
                              noteId: _selectedNoteId!,
                              autoFocusTitle: _autoFocusTitle,
                              controller: _editorController,
                              onDelete: () => setState(() {
                                _selectedNoteId = null;
                                _autoFocusTitle = false;
                              }),
                            )
                          : Center(
                              child: Text(
                                'Select a note',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.4),
                                  fontSize: 16,
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              }

              return _buildNoteList(context, notes, false, theme, cs);
            },
          );
        },
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _NoteListTile({
    required this.note,
    required this.isSelected,
    required this.onTap,
    required this.onPin,
    required this.onDelete,
  });

  String _relativeDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(dt.year, dt.month, dt.day)).inDays;
    if (diff == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
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
    final m = months[dt.month - 1];
    return dt.year != now.year ? '$m ${dt.day}, ${dt.year}' : '$m ${dt.day}';
  }

  String _preview(Note note) {
    final raw = note.content.trim();
    if (raw.isEmpty) return 'No content';
    final line = raw.split('\n').first;
    return line.length > 80 ? '${line.substring(0, 80)}…' : line;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = note.title.isEmpty ? '(Untitled)' : note.title;
    final onSurface = isSelected ? cs.onPrimaryContainer : cs.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: isSelected
            ? cs.primaryContainer
            : (theme.brightness == Brightness.dark
                  ? cs.surfaceContainerHigh
                  : cs.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _relativeDate(note.updatedAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _preview(note),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.push_pin),
                  iconSize: 16,
                  color: note.pinned
                      ? (isSelected ? cs.onPrimaryContainer : cs.primary)
                      : onSurface.withValues(alpha: 0.25),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  tooltip: note.pinned ? 'Unpin' : 'Pin',
                  onPressed: onPin,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  iconSize: 16,
                  color: onSurface.withValues(alpha: 0.3),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Trash screen ─────────────────────────────────────────────────────────────

class _TrashScreen extends ConsumerWidget {
  const _TrashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDeleted = ref.watch(deletedNoteListProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trash',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
      ),
      body: asyncDeleted.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notes) => notes.isEmpty
            ? Center(
                child: Text(
                  'Trash is empty',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 16,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: notes.length,
                itemBuilder: (_, i) => _TrashNoteTile(note: notes[i]),
              ),
      ),
    );
  }
}

class _TrashNoteTile extends ConsumerWidget {
  final Note note;
  const _TrashNoteTile({required this.note});

  String _deletedAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
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
    final m = months[dt.month - 1];
    return dt.year != now.year ? '$m ${dt.day}, ${dt.year}' : '$m ${dt.day}';
  }

  Future<void> _confirmPermanentDelete(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text('This note will be gone and cannot be recovered.'),
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
      await ref
          .read(deletedNoteListProvider.notifier)
          .permanentlyDelete(note.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = note.title.isEmpty ? '(Untitled)' : note.title;
    final deletedAt = note.deletedAt ?? DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: theme.brightness == Brightness.dark
            ? cs.surfaceContainerHigh
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Deleted ${_deletedAgo(deletedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.restore),
                iconSize: 20,
                tooltip: 'Restore',
                onPressed: () =>
                    ref.read(deletedNoteListProvider.notifier).restore(note.id),
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever_outlined),
                iconSize: 20,
                tooltip: 'Delete permanently',
                color: cs.error,
                onPressed: () => _confirmPermanentDelete(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
