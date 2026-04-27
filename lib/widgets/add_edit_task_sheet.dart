import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/recurrence.dart';
import '../providers/settings_providers.dart';
import '../providers/task_providers.dart';
import '../utils/date_utils.dart' as du;

class AddEditTaskSheet extends ConsumerStatefulWidget {
  final Task? task;
  final bool editAllInSeries;
  final DateTime? initialDate;

  const AddEditTaskSheet({
    super.key,
    this.task,
    this.editAllInSeries = false,
    this.initialDate,
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
    _dueDate = t?.dueDate ?? widget.initialDate ?? DateTime.now();
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
    final notes = _notesCtrl.text.trim().isEmpty
        ? null
        : _notesCtrl.text.trim();

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
    final dateStyle = ref.watch(dateFormatNotifierProvider);
    final timeStyle = ref.watch(timeFormatNotifierProvider);

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
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            sheetTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_isEditAll) ...[
            const SizedBox(height: 4),
            Text(
              'Updates title, time, notes, and recurrence for all remaining tasks in this series.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (!_isEditAll) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      du.formatDateAs(_dueDate, dateStyle),
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      du.formatTimeAs(_dueTime, timeStyle),
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_isEditAll) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time, size: 16),
              label: Text(
                du.formatTimeAs(_dueTime, timeStyle),
                style: const TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<RecurrenceType>(
            initialValue: _recurrence,
            decoration: const InputDecoration(
              labelText: 'Repeats',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: RecurrenceType.values
                .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                .toList(),
            onChanged: (v) => setState(() => _recurrence = v!),
          ),
          const SizedBox(height: 14),
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
