import 'package:flutter/material.dart';
import '../models/task.dart';
import '../utils/date_utils.dart' as du;
import 'task_card.dart';

class DateGroupCard extends StatelessWidget {
  final DateTime date;
  final List<Task> tasks;
  final bool isOverdueGroup;

  const DateGroupCard({
    super.key,
    required this.date,
    required this.tasks,
    this.isOverdueGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardColor = isOverdueGroup
        ? (isDark
            ? Colors.red.shade900.withValues(alpha: 0.35)
            : Colors.red.shade50)
        : (isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerHighest);

    final headerColor = isOverdueGroup
        ? Colors.red.shade300
        : colorScheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                du.formatDateGroupHeader(date),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: headerColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ...tasks.map((t) => TaskCard(task: t)),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
