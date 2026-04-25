import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/supabase_provider.dart';
import '../providers/task_providers.dart';
import '../providers/theme_provider.dart';
import '../widgets/add_edit_task_sheet.dart';
import '../widgets/completed_task_card.dart';
import '../widgets/simple_list_section.dart';
import '../widgets/task_section.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _simpleListExpanded = true;
  bool _completedExpanded = true;

  void _openAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddEditTaskSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeNotifierProvider);
    final taskListAsync = ref.watch(taskListProvider);
    final overdue = ref.watch(overdueTasksProvider);
    final upcoming = ref.watch(upcomingTasksProvider);
    final completedAsync = ref.watch(completedTaskListProvider);
    final showAllCompleted = ref.watch(showAllCompletedProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final activeTasks = taskListAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (_) {
        return CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _SectionHeader(
                title: 'SIMPLE LIST',
                theme: theme,
                isExpanded: _simpleListExpanded,
                onTap: () => setState(
                    () => _simpleListExpanded = !_simpleListExpanded),
              ),
            ),
            if (_simpleListExpanded) ...[
              const SliverToBoxAdapter(child: SimpleListSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
            if (overdue.isNotEmpty) ...[
              SliverPersistentHeader(
                pinned: true,
                delegate: _SectionHeader(
                  title: 'OVERDUE',
                  color: Colors.red.shade400,
                  theme: theme,
                ),
              ),
              TaskSection(tasks: overdue, isOverdueSection: true),
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
            if (overdue.isEmpty && upcoming.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text(
                      'All clear',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      },
    );

    final completedHeader = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(
                  () => _completedExpanded = !_completedExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'COMPLETED',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _completedExpanded
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_completedExpanded)
            completedAsync.maybeWhen(
              data: (completed) => completed.isNotEmpty
                  ? TextButton(
                      onPressed: () => ref
                          .read(showAllCompletedProvider.notifier)
                          .state = !showAllCompleted,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                          showAllCompleted ? 'Show less' : 'Show more'),
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tasks',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () =>
                ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: activeTasks),
          const Divider(height: 1),
          if (_completedExpanded)
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    completedHeader,
                    Expanded(
                      child: completedAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const SizedBox.shrink(),
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
            )
          else
            completedHeader,
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_tasks',
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
  final bool? isExpanded;
  final VoidCallback? onTap;

  const _SectionHeader({
    required this.title,
    this.color,
    required this.theme,
    this.isExpanded,
    this.onTap,
  });

  @override
  double get minExtent => 36;
  @override
  double get maxExtent => 36;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final labelColor =
        color ?? theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final row = Row(
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: labelColor,
            letterSpacing: 0.8,
          ),
        ),
        if (isExpanded != null) ...[
          const SizedBox(width: 4),
          Icon(
            isExpanded! ? Icons.expand_more : Icons.chevron_right,
            size: 18,
            color: labelColor,
          ),
        ],
      ],
    );

    final content = Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      alignment: Alignment.centerLeft,
      child: row,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }

  @override
  bool shouldRebuild(_SectionHeader old) =>
      old.title != title ||
      old.color != color ||
      old.isExpanded != isExpanded ||
      old.theme.brightness != theme.brightness ||
      old.theme.colorScheme != theme.colorScheme;
}
