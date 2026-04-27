import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/supabase_provider.dart';
import '../providers/task_providers.dart';
import '../widgets/add_edit_task_sheet.dart';
import '../widgets/calendar_view.dart';
import '../widgets/completed_task_card.dart';
import '../widgets/simple_list_section.dart';
import '../widgets/task_section.dart';

enum _TasksView { list, calendar }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _TasksView _view = _TasksView.list;
  bool _simpleListExpanded = true;
  bool _completedExpanded = false;
  DateTime _selectedCalendarDay = DateTime.now();

  void _openAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddEditTaskSheet(
        initialDate:
            _view == _TasksView.calendar ? _selectedCalendarDay : null,
      ),
    );
  }

  Widget _buildSimpleListSection(ThemeData theme, ColorScheme colorScheme) {
    final header = InkWell(
      onTap: () =>
          setState(() => _simpleListExpanded = !_simpleListExpanded),
      child: Container(
        color: theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Text(
              'QUICK LIST',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _simpleListExpanded
                  ? Icons.expand_more
                  : Icons.chevron_right,
              size: 18,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (_simpleListExpanded) ...[
          const SimpleListSection(),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildListView(ThemeData theme, ColorScheme colorScheme) {
    final taskListAsync = ref.watch(taskListProvider);
    final overdue = ref.watch(overdueTasksProvider);
    final upcoming = ref.watch(upcomingTasksProvider);
    final completedAsync = ref.watch(completedTaskListProvider);
    final showAllCompleted = ref.watch(showAllCompletedProvider);

    final activeTasks = taskListAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (_) {
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

    return Column(
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
    );
  }

  Widget _buildViewToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SegmentedButton<_TasksView>(
        segments: const [
          ButtonSegment(
            value: _TasksView.list,
            label: Text('List'),
            icon: Icon(Icons.view_list_outlined, size: 16),
          ),
          ButtonSegment(
            value: _TasksView.calendar,
            label: Text('Calendar'),
            icon: Icon(Icons.calendar_month_outlined, size: 16),
          ),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final body = _view == _TasksView.list
        ? _buildListView(theme, colorScheme)
        : CalendarView(
            initialSelectedDay: _selectedCalendarDay,
            onDaySelected: (day) =>
                setState(() => _selectedCalendarDay = day),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tasks',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: const [],
      ),
      body: Column(
        children: [
          _buildViewToggle(),
          _buildSimpleListSection(theme, colorScheme),
          Expanded(child: body),
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

  const _SectionHeader({
    required this.title,
    this.color,
    required this.theme,
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

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: labelColor,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeader old) =>
      old.title != title ||
      old.color != color ||
      old.theme.brightness != theme.brightness ||
      old.theme.colorScheme != theme.colorScheme;
}
