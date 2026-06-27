import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tracker_metric.dart';
import '../providers/settings_providers.dart';
import '../providers/tracker_providers.dart';
import '../utils/date_utils.dart' as du;
import '../utils/tracker_overview_stats.dart';
import 'tracker_metric_screen.dart';

class TrackerScreen extends ConsumerWidget {
  const TrackerScreen({super.key});

  Future<void> _createMetric(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final unitController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New metric'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Weight, Steps',
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit (optional)',
                  hintText: 'e.g. kg, count',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await ref
          .read(trackerMetricsProvider.notifier)
          .create(
            name: nameController.text.trim(),
            unit: unitController.text.trim().isEmpty
                ? null
                : unitController.text.trim(),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMetrics = ref.watch(trackerMetricsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text(
          'Tracker',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: const [],
      ),
      body: asyncMetrics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (metrics) {
          if (metrics.isEmpty) {
            return const Center(
              child: Text(
                'No metrics yet — tap + to add one',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: metrics.length,
            itemBuilder: (_, i) => _MetricCard(
              metric: metrics[i],
              theme: theme,
              colorScheme: colorScheme,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_tracker',
        onPressed: () => _createMetric(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _MetricCard extends ConsumerWidget {
  final TrackerMetric metric;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _MetricCard({
    required this.metric,
    required this.theme,
    required this.colorScheme,
  });

  String _formatValue(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _formatStatValue(double value) {
    final formatted = _formatValue(value);
    return metric.unit == null ? formatted : '$formatted ${metric.unit}';
  }

  String _formatLastLogged(DateTime? date, DateFormatStyle dateStyle) {
    if (date == null) return '-';

    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final loggedDate = DateTime(local.year, local.month, local.day);
    final daysAgo = today.difference(loggedDate).inDays;

    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    return du.formatDateAs(local, dateStyle);
  }

  Future<void> _editMetric(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController(text: metric.name);
    final unitController = TextEditingController(text: metric.unit ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit metric'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit (optional)',
                  hintText: 'e.g. kg, count',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final newUnit = unitController.text.trim().isEmpty
          ? null
          : unitController.text.trim();
      await ref
          .read(trackerMetricsProvider.notifier)
          .editMetric(
            metric.id,
            name: nameController.text.trim(),
            unit: newUnit,
            clearUnit: newUnit == null && metric.unit != null,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEntries = ref.watch(trackerEntriesProvider(metric.id));
    final dateStyle = ref.watch(dateFormatNotifierProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: theme.brightness == Brightness.dark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TrackerMetricScreen(metric: metric),
            ),
          ),
          onLongPress: () => _editMetric(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: asyncEntries.when(
              loading: () => _MetricCardContent(
                metricName: metric.name,
                stats: null,
                dateStyle: dateStyle,
                formatStatValue: _formatStatValue,
                formatLastLogged: _formatLastLogged,
                theme: theme,
                colorScheme: colorScheme,
              ),
              error: (_, _) => _MetricCardContent(
                metricName: metric.name,
                stats: null,
                dateStyle: dateStyle,
                formatStatValue: _formatStatValue,
                formatLastLogged: _formatLastLogged,
                theme: theme,
                colorScheme: colorScheme,
              ),
              data: (entries) => _MetricCardContent(
                metricName: metric.name,
                stats: buildTrackerOverviewStats(
                  entries: entries,
                  now: DateTime.now(),
                ),
                dateStyle: dateStyle,
                formatStatValue: _formatStatValue,
                formatLastLogged: _formatLastLogged,
                theme: theme,
                colorScheme: colorScheme,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCardContent extends StatelessWidget {
  final String metricName;
  final TrackerOverviewStats? stats;
  final DateFormatStyle dateStyle;
  final String Function(double value) formatStatValue;
  final String Function(DateTime? date, DateFormatStyle dateStyle)
  formatLastLogged;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _MetricCardContent({
    required this.metricName,
    required this.stats,
    required this.dateStyle,
    required this.formatStatValue,
    required this.formatLastLogged,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final values = stats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metricName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _TrackerStatBlock(
              label: 'Last logged',
              value: values == null
                  ? '...'
                  : formatLastLogged(values.lastLoggedAt, dateStyle),
              theme: theme,
              colorScheme: colorScheme,
            ),
            _TrackerStatBlock(
              label: 'Last 7 days',
              value: values == null
                  ? '...'
                  : formatStatValue(values.lastSevenDaysTotal),
              theme: theme,
              colorScheme: colorScheme,
            ),
            _TrackerStatBlock(
              label: _currentMonthLabel(),
              value: values == null
                  ? '...'
                  : formatStatValue(values.currentMonthTotal),
              theme: theme,
              colorScheme: colorScheme,
            ),
            _TrackerStatBlock(
              label: '30d avg',
              value: values == null
                  ? '...'
                  : formatStatValue(values.thirtyDayAverage),
              theme: theme,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ],
    );
  }

  String _currentMonthLabel() {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[now.month - 1]} ${now.year}';
  }
}

class _TrackerStatBlock extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _TrackerStatBlock({
    required this.label,
    required this.value,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.58),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.86),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
