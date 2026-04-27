import 'package:flutter/material.dart';

import '../widgets/note_editor_pane.dart';

class NoteEditorScreen extends StatelessWidget {
  final String noteId;
  final bool autoFocusTitle;

  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.autoFocusTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Note')),
      body: NoteEditorPane(
        noteId: noteId,
        autoFocusTitle: autoFocusTitle,
        onDelete: () => Navigator.of(context).pop(),
      ),
    );
  }
}
