import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_providers.dart';
import '../providers/theme_provider.dart';
import '../widgets/add_edit_task_sheet.dart';
import '../widgets/completed_task_card.dart';
import '../widgets/task_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _openAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddEditTaskSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);
    final taskListAsync = ref.watch(taskListProvider);
    final overdue = ref.watch(overdueTasksProvider);
    final upcoming = ref.watch(upcomingTasksProvider);
    final completedAsync = ref.watch(completedTaskListProvider);
    final showAllCompleted = ref.watch(showAllCompletedProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon/slate.png', height: 28, width: 28),
            const SizedBox(width: 8),
            const Text(
              'Slate',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            tooltip: 'Toggle theme',
            onPressed: () =>
                ref.read(themeNotifierProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New task',
            onPressed: () => _openAdd(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Active tasks (70%) ──────────────────────────────────────────
          Flexible(
            flex: 7,
            child: taskListAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) {
                if (overdue.isEmpty && upcoming.isEmpty) {
                  return const Center(
                    child: Text(
                      'All clear',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }
                return CustomScrollView(
                  slivers: [
                    if (overdue.isNotEmpty) ...[
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SectionHeader(
                          title: 'OVERDUE',
                          color: Colors.red.shade400,
                          theme: theme,
                        ),
                      ),
                      TaskSection(tasks: overdue),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SectionHeader(
                          title: 'UPCOMING',
                          theme: theme,
                        ),
                      ),
                      TaskSection(tasks: upcoming),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                );
              },
            ),
          ),

          // ── Divider ─────────────────────────────────────────────────────
          const Divider(height: 1),

          // ── Completed tasks (30%) ────────────────────────────────────────
          Flexible(
            flex: 3,
            child: Column(
              children: [
                // Section header row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        'COMPLETED',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color:
                              colorScheme.onSurface.withValues(alpha: 0.6),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const Spacer(),
                      completedAsync.maybeWhen(
                        data: (completed) => completed.isNotEmpty
                            ? TextButton(
                                onPressed: () => ref
                                    .read(showAllCompletedProvider.notifier)
                                    .state = !showAllCompleted,
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(showAllCompleted
                                    ? 'Show less'
                                    : 'Show more'),
                              )
                            : const SizedBox.shrink(),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),

                // Scrollable completed list
                Expanded(
                  child: completedAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator()),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (completed) => completed.isEmpty
                        ? Center(
                            child: Text(
                              'No completed tasks',
                              style: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: completed.length,
                            itemBuilder: (_, i) =>
                                CompletedTaskCard(task: completed[i]),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAdd(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SectionHeader extends SliverPersistentHeaderDelegate {
  final String title;
  final Color? color;
  final ThemeData theme;

  const _SectionHeader({required this.title, this.color, required this.theme});

  @override
  double get minExtent => 36;
  @override
  double get maxExtent => 36;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: color ?? theme.colorScheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeader old) =>
      old.title != title || old.color != color;
}
