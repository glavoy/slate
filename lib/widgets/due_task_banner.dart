import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../providers/settings_providers.dart';
import '../providers/task_alert_providers.dart';
import '../providers/task_providers.dart';
import '../services/task_alert_rules.dart';
import '../utils/date_utils.dart';

/// Rows visible before the expanded list starts scrolling.
const _visibleRows = 3;
const _rowHeight = 60.0;

/// App-level banner announcing tasks that have come due.
///
/// Collapsed it shows the most overdue task with a count of the rest; expanded
/// it lists them all, each with its own actions.
class DueTaskBanner extends ConsumerStatefulWidget {
  const DueTaskBanner({super.key});

  @override
  ConsumerState<DueTaskBanner> createState() => _DueTaskBannerState();
}

class _DueTaskBannerState extends ConsumerState<DueTaskBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(dueAlertsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Collapse again once the queue no longer justifies a list.
    if (_expanded && alerts.length <= 1) {
      _expanded = false;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: alerts.isEmpty
          ? const SizedBox(width: double.infinity, height: 0)
          : Material(
              color: colorScheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: _expanded
                    ? _buildExpanded(alerts, colorScheme)
                    : _DueTaskRow(
                        task: alerts.first,
                        colorScheme: colorScheme,
                        trailingCount: alerts.length - 1,
                        onExpand: () => setState(() => _expanded = true),
                      ),
              ),
            ),
    );
  }

  Widget _buildExpanded(List<Task> alerts, ColorScheme colorScheme) {
    final onContainer = colorScheme.onErrorContainer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8, top: 8),
          child: Row(
            children: [
              Icon(Icons.notifications_active, size: 20, color: onContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${alerts.length} tasks due',
                  style: TextStyle(
                    color: onContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(dueAlertsProvider.notifier).dismissAll(),
                style: TextButton.styleFrom(foregroundColor: onContainer),
                child: const Text('Dismiss all'),
              ),
              IconButton(
                icon: const Icon(Icons.expand_less),
                color: onContainer,
                tooltip: 'Collapse',
                onPressed: () => setState(() => _expanded = false),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: _rowHeight * _visibleRows,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: alerts.length,
            itemBuilder: (context, index) => _DueTaskRow(
              task: alerts[index],
              colorScheme: colorScheme,
              trailingCount: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _DueTaskRow extends ConsumerWidget {
  const _DueTaskRow({
    required this.task,
    required this.colorScheme,
    required this.trailingCount,
    this.onExpand,
  });

  final Task task;
  final ColorScheme colorScheme;

  /// How many further alerts are queued behind this one; 0 hides the chip.
  final int trailingCount;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onContainer = colorScheme.onErrorContainer;
    final dayStart = ref.watch(taskAlertDayStartNotifierProvider);
    final timeFormat = ref.watch(timeFormatNotifierProvider);
    final dueAt = resolveDueAt(task.dueDate, task.dueTime, dayStart);

    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            if (onExpand != null) ...[
              Icon(Icons.notifications_active, size: 20, color: onContainer),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _subtitle(dueAt, timeFormat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onContainer.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingCount > 0)
              TextButton(
                onPressed: onExpand,
                style: TextButton.styleFrom(foregroundColor: onContainer),
                child: Text('+$trailingCount more'),
              ),
            IconButton(
              icon: const Icon(Icons.check),
              color: onContainer,
              tooltip: 'Mark done',
              onPressed: () =>
                  ref.read(taskListProvider.notifier).markDone(task),
            ),
            PopupMenuButton<DateTime>(
              icon: Icon(Icons.snooze, color: onContainer),
              tooltip: 'Snooze',
              onSelected: (until) =>
                  ref.read(dueAlertsProvider.notifier).snoozeUntil(task, until),
              itemBuilder: (context) => [
                for (final target in snoozeTargets(DateTime.now(), dayStart))
                  PopupMenuItem(value: target.at, child: Text(target.label)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: onContainer,
              tooltip: 'Dismiss',
              onPressed: () =>
                  ref.read(dueAlertsProvider.notifier).dismiss(task),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(DateTime dueAt, TimeFormatStyle timeFormat) {
    final time = formatTimeAs(TimeOfDay.fromDateTime(dueAt), timeFormat);
    final elapsed = DateTime.now().difference(dueAt);

    if (elapsed.inMinutes < 1) return 'Due now · $time';
    if (elapsed.inMinutes < 60) {
      return 'Overdue by ${elapsed.inMinutes}m · $time';
    }
    if (elapsed.inHours < 24) return 'Overdue by ${elapsed.inHours}h · $time';
    return 'Overdue · ${formatDate(dueAt)} $time';
  }
}
