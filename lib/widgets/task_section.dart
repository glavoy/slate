import 'package:flutter/material.dart';
import '../models/task.dart';
import 'task_card.dart';

class TaskSection extends StatelessWidget {
  final List<Task> tasks;

  const TaskSection({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverMainAxisGroup(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => TaskCard(task: tasks[index]),
            childCount: tasks.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}
