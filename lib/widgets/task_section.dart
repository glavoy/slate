import 'package:flutter/material.dart';
import '../models/task.dart';
import 'date_group_card.dart';

class TaskSection extends StatelessWidget {
  final List<Task> tasks;
  final bool isOverdueSection;

  const TaskSection({
    super.key,
    required this.tasks,
    this.isOverdueSection = false,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final groups = <DateTime, List<Task>>{};
    for (final t in tasks) {
      final key = DateTime(t.dueDate.year, t.dueDate.month, t.dueDate.day);
      (groups[key] ??= []).add(t);
    }

    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return SliverMainAxisGroup(
      slivers: [
        SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (_, i) => DateGroupCard(
            date: entries[i].key,
            tasks: entries[i].value,
            isOverdueGroup: isOverdueSection,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}
