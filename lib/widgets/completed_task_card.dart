import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recurrence.dart';
import '../models/task.dart';
import '../providers/settings_providers.dart';
import '../providers/task_providers.dart';
import '../utils/date_utils.dart' as du;

class CompletedTaskCard extends ConsumerWidget {
  final Task task;

  const CompletedTaskCard({super.key, required this.task});

  bool get _isRecurring => task.recurrence != RecurrenceType.none;
  bool get _hasSeries => task.seriesId != null;

  Future<void> _handleUndo(BuildContext context, WidgetRef ref) async {
    if (_isRecurring && _hasSeries) {
      final dateStyle = ref.read(dateFormatNotifierProvider);
      final nextDue = du.formatDateAs(
          du.nextOccurrence(task.dueDate, task.recurrence), dateStyle);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore task?'),
          content: Text(
            '"${task.title}" will be moved back to active.\n\n'
            'The next scheduled occurrence ($nextDue) will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    await ref.read(completedTaskListProvider.notifier).undoComplete(task);
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete completed task?'),
        content: Text('"${task.title}" will be permanently deleted.'),
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
      await ref.read(completedTaskListProvider.notifier).delete(task.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateStyle = ref.watch(dateFormatNotifierProvider);
    final completedText = task.completedAt != null
        ? 'Completed ${du.formatDateAs(task.completedAt!, dateStyle)}'
        : 'Completed';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 22,
              color: colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      decoration: TextDecoration.lineThrough,
                      decorationColor:
                          colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    completedText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.undo,
                size: 20,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
              onPressed: () => _handleUndo(context, ref),
              tooltip: 'Mark as not done',
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              onPressed: () => _handleDelete(context, ref),
              tooltip: 'Delete permanently',
            ),
          ],
        ),
      ),
    );
  }
}
