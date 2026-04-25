import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/note_providers.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;
  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  Timer? _debounce;
  String _lastSavedTitle = '';
  String _lastSavedContent = '';
  bool _initialized = false;

  static const _debounceDuration = Duration(milliseconds: 1000);

  @override
  void dispose() {
    _debounce?.cancel();
    // Flush any pending save synchronously before disposing
    _flushIfDirty();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _flushIfDirty() {
    final t = _titleController.text;
    final c = _contentController.text;
    if (!_initialized) return;
    if (t == _lastSavedTitle && c == _lastSavedContent) return;
    _lastSavedTitle = t;
    _lastSavedContent = c;
    ref.read(noteListProvider.notifier).edit(
          widget.noteId,
          title: t,
          content: c,
        );
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flushIfDirty);
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
      if (context.mounted) Navigator.of(context).pop();
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
    final asyncNotes = ref.watch(noteListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _flushIfDirty();
            Navigator.of(context).pop();
          },
        ),
        title: const Text('Note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete note',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: asyncNotes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notes) {
          final note = _findNote(notes);
          if (note == null) {
            return const Center(child: Text('Note not found'));
          }
          if (!_initialized) {
            _titleController.text = note.title;
            _contentController.text = note.content;
            _lastSavedTitle = note.title;
            _lastSavedContent = note.content;
            _initialized = true;
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleController,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => _scheduleSave(),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Start writing…',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (_) => _scheduleSave(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
