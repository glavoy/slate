import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/task.dart';
import '../models/recurrence.dart';
import '../providers/task_providers.dart';
import '../utils/date_utils.dart' as du;
import 'add_edit_task_sheet.dart';

class TaskCard extends ConsumerStatefulWidget {
  final Task task;

  const TaskCard({super.key, required this.task});

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _expanded = false;

  Task get task => widget.task;
  bool get _isRecurring => task.recurrence != RecurrenceType.none;
  bool get _hasSeries => task.seriesId != null;
  bool get _hasNotes => task.notes != null && task.notes!.isNotEmpty;

  // ── Context menu (right-click, macOS) ───────────────────────────────────

  Future<void> _showContextMenu(
      BuildContext context, TapUpDetails details) async {
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
        await _deleteSingle(context);
      case 'delete_all':
        await _deleteAll(context);
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

  Future<void> _handleSwipeDelete(BuildContext context) async {
    if (_isRecurring) {
      await _deleteSeriesDialog(context);
    } else {
      await _deleteSingle(context);
    }
  }

  Future<void> _deleteSingle(BuildContext context) async {
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

  Future<void> _deleteAll(BuildContext context) async {
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

  Future<void> _deleteSeriesDialog(BuildContext context) async {
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
  Widget build(BuildContext context) {
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Slidable(
      key: ValueKey(task.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (ctx) => _handleSwipeDelete(ctx),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isMacOS ? null : () => _handleTap(context),
        onSecondaryTapUp: isMacOS
            ? (details) => _showContextMenu(context, details)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Checkbox(
                    value: task.isDone,
                    shape: const CircleBorder(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) =>
                        ref.read(taskListProvider.notifier).markDone(task),
                  ),
                  const SizedBox(width: 8),
                  if (task.dueTime != null) ...[
                    SizedBox(
                      width: 64,
                      child: Text(
                        du.formatTime(du.parseTime(task.dueTime!)),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      task.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (task.recurrence != RecurrenceType.none) ...[
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
                    const SizedBox(width: 4),
                  ],
                  if (_hasNotes)
                    IconButton(
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.notes,
                        size: 20,
                        color: _expanded
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      tooltip: _expanded ? 'Hide note' : 'Show note',
                      onPressed: () =>
                          setState(() => _expanded = !_expanded),
                    ),
                ],
              ),
            ),
            if (_expanded && _hasNotes)
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                child: Text(
                  task.notes!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
