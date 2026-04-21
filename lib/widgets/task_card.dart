import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/task.dart';
import '../models/recurrence.dart';
import '../providers/task_providers.dart';
import '../utils/date_utils.dart' as du;
import 'add_edit_task_sheet.dart';

class TaskCard extends ConsumerWidget {
  final Task task;

  const TaskCard({super.key, required this.task});

  bool get _isRecurring => task.recurrence != RecurrenceType.none;
  bool get _hasSeries => task.seriesId != null;

  // ── Context menu (right-click, macOS) ───────────────────────────────────

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, TapUpDetails details) async {
    final pos = details.globalPosition;
    final rect = RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy);

    final items = <PopupMenuEntry<String>>[
      if (_isRecurring) ...[
        const PopupMenuItem(value: 'edit_single', child: Text('Edit this task only')),
        if (_hasSeries)
          const PopupMenuItem(value: 'edit_all', child: Text('Edit all remaining')),
      ] else
        const PopupMenuItem(value: 'edit_single', child: Text('Edit task')),
      const PopupMenuDivider(),
      if (_isRecurring) ...[
        PopupMenuItem(
          value: 'delete_single',
          child: Text('Delete this task only',
              style: TextStyle(color: Colors.red.shade400)),
        ),
        if (_hasSeries)
          PopupMenuItem(
            value: 'delete_all',
            child: Text('Delete all remaining',
                style: TextStyle(color: Colors.red.shade400)),
          ),
      ] else
        PopupMenuItem(
          value: 'delete_single',
          child: Text('Delete task',
              style: TextStyle(color: Colors.red.shade400)),
        ),
    ];

    final choice =
        await showMenu<String>(context: context, position: rect, items: items);

    if (!context.mounted) return;

    switch (choice) {
      case 'edit_single':
        _openSheet(context, editAllInSeries: false);
      case 'edit_all':
        _openSheet(context, editAllInSeries: true);
      case 'delete_single':
        await _deleteSingle(context, ref);
      case 'delete_all':
        await _deleteAll(context, ref);
    }
  }

  // ── Tap (Android only) ──────────────────────────────────────────────────

  Future<void> _handleTap(BuildContext context) async {
    if (!_isRecurring || !_hasSeries) {
      _openSheet(context, editAllInSeries: false);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit recurring task'),
        content: const Text(
            'Edit just this task, or all remaining tasks in the series?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('single'),
            child: const Text('This task only'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('all'),
            child: const Text('All remaining'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'single') _openSheet(context, editAllInSeries: false);
    if (choice == 'all') _openSheet(context, editAllInSeries: true);
  }

  // ── Swipe delete ─────────────────────────────────────────────────────────

  Future<void> _handleSwipeDelete(BuildContext context, WidgetRef ref) async {
    if (_isRecurring) {
      await _deleteSeriesDialog(context, ref);
    } else {
      await _deleteSingle(context, ref);
    }
  }

  Future<void> _deleteSingle(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
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
      await ref.read(taskListProvider.notifier).delete(task.id);
    }
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all remaining?'),
        content: Text(
            'All remaining "${task.title}" tasks in this series will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(taskListProvider.notifier).deleteSeries(task.seriesId!);
    }
  }

  Future<void> _deleteSeriesDialog(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recurring task?'),
        content: const Text(
            'Delete just this task, or all remaining tasks in the series?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('single'),
            child: const Text('This task only'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('all'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('All remaining'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'single') {
      await ref.read(taskListProvider.notifier).delete(task.id);
    } else if (choice == 'all') {
      await ref.read(taskListProvider.notifier).deleteSeries(task.seriesId!);
    }
  }

  void _openSheet(BuildContext context, {required bool editAllInSeries}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          AddEditTaskSheet(task: task, editAllInSeries: editAllInSeries),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue = du.isOverdue(task.dueDate);
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardColor = overdue
        ? Color.lerp(colorScheme.surface, Colors.red, 0.08)!
        : colorScheme.surface;

    return Slidable(
      key: ValueKey(task.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (ctx) => _handleSwipeDelete(ctx, ref),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(12)),
          ),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isMacOS ? null : () => _handleTap(context),
        onSecondaryTapUp: isMacOS
            ? (details) => _showContextMenu(context, ref, details)
            : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: overdue ? Colors.red.shade500 : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Checkbox(
                  value: task.isDone,
                  shape: const CircleBorder(),
                  onChanged: (_) =>
                      ref.read(taskListProvider.notifier).markDone(task),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            [
                              du.formatDate(task.dueDate),
                              if (task.dueTime != null)
                                du.formatTime(du.parseTime(task.dueTime!)),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: overdue
                                  ? Colors.red.shade400
                                  : colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                            ),
                          ),
                          if (task.recurrence != RecurrenceType.none) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                task.recurrence.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (task.notes != null && task.notes!.isNotEmpty)
                  Icon(Icons.notes,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
