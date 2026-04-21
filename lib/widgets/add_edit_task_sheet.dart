import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/recurrence.dart';
import '../providers/task_providers.dart';
import '../utils/date_utils.dart' as du;

class AddEditTaskSheet extends ConsumerStatefulWidget {
  final Task? task;
  final bool editAllInSeries;

  const AddEditTaskSheet({
    super.key,
    this.task,
    this.editAllInSeries = false,
  });

  @override
  ConsumerState<AddEditTaskSheet> createState() => _AddEditTaskSheetState();
}

class _AddEditTaskSheetState extends ConsumerState<AddEditTaskSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _dueDate;
  late TimeOfDay _dueTime;
  late RecurrenceType _recurrence;
  bool _saving = false;

  bool get _isNew => widget.task == null;
  bool get _isEditAll => widget.editAllInSeries;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _notesCtrl = TextEditingController(text: t?.notes ?? '');
    _dueDate = t?.dueDate ?? DateTime.now();
    _dueTime = t?.dueTime != null
        ? du.parseTime(t!.dueTime!)
        : du.defaultDueTime;
    _recurrence = t?.recurrence ?? RecurrenceType.none;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime,
    );
    if (picked != null) setState(() => _dueTime = picked);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    setState(() => _saving = true);
    try {
      final notifier = ref.read(taskListProvider.notifier);

      if (_isNew) {
        await notifier.add(
          title: title,
          dueDate: _dueDate,
          dueTime: _dueTime,
          notes: notes,
          recurrence: _recurrence,
        );
      } else if (_isEditAll) {
        await notifier.editAllInSeries(
          seriesId: widget.task!.seriesId!,
          title: title,
          dueTime: _dueTime,
          notes: notes,
          recurrence: _recurrence,
        );
      } else {
        await notifier.editTask(
          taskId: widget.task!.id,
          title: title,
          dueDate: _dueDate,
          dueTime: _dueTime,
          notes: notes,
          recurrence: _recurrence,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String sheetTitle;
    if (_isNew) {
      sheetTitle = 'New Task';
    } else if (_isEditAll) {
      sheetTitle = 'Edit All in Series';
    } else {
      sheetTitle = 'Edit Task';
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(sheetTitle, style: theme.textTheme.titleLarge),
          if (_isEditAll) ...[
            const SizedBox(height: 6),
            Text(
              'Updates title, time, notes, and recurrence for all remaining tasks in this series.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (!_isEditAll) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(du.formatDate(_dueDate)),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(du.formatTime(_dueTime)),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_isEditAll) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time, size: 18),
              label: Text(du.formatTime(_dueTime)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<RecurrenceType>(
            value: _recurrence,
            decoration: const InputDecoration(
              labelText: 'Repeats',
              border: OutlineInputBorder(),
            ),
            items: RecurrenceType.values
                .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                .toList(),
            onChanged: (v) => setState(() => _recurrence = v!),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isNew ? 'Add Task' : 'Save Changes'),
          ),
        ],
      ),
    );
  }
}
