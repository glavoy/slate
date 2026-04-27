import 'package:flutter/material.dart';

import '../widgets/note_editor_pane.dart';

class NoteEditorScreen extends StatefulWidget {
  final String noteId;
  final bool autoFocusTitle;

  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.autoFocusTitle = false,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _editorController = NoteEditorController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_list_bulleted),
            iconSize: 20,
            tooltip: 'Toggle bullet',
            onPressed: _editorController.toggleBullet,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: 20,
            tooltip: 'Delete note',
            onPressed: () => _editorController.confirmDelete(context),
          ),
        ],
      ),
      body: NoteEditorPane(
        noteId: widget.noteId,
        autoFocusTitle: widget.autoFocusTitle,
        controller: _editorController,
        onDelete: () => Navigator.of(context).pop(),
      ),
    );
  }
}
