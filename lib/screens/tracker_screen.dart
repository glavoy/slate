import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tracker_metric.dart';
import '../providers/tracker_providers.dart';
import '../widgets/sparkline.dart';
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
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Required' : null,
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
      await ref.read(trackerMetricsProvider.notifier).create(
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
            itemBuilder: (_, i) =>
                _MetricCard(metric: metrics[i], theme: theme, colorScheme: colorScheme),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEntries = ref.watch(trackerEntriesProvider(metric.id));

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
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      asyncEntries.when(
                        loading: () => Text(
                          '…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (entries) => Text(
                          entries.isEmpty
                              ? 'No entries'
                              : '${_formatValue(entries.first.value)}${metric.unit != null ? ' ${metric.unit}' : ''} · ${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  height: 36,
                  child: asyncEntries.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (entries) => Sparkline(
                      values:
                          entries.reversed.map((e) => e.value).toList(),
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
