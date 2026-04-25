import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tracker_entry.dart';
import '../models/tracker_metric.dart';
import '../providers/settings_providers.dart';
import '../providers/tracker_providers.dart';
import '../utils/date_utils.dart' as du;
import '../widgets/sparkline.dart';

class TrackerMetricScreen extends ConsumerWidget {
  final TrackerMetric metric;
  const TrackerMetricScreen({super.key, required this.metric});

  String _formatValue(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _formatRecorded(
      DateTime dt, DateFormatStyle dateStyle, TimeFormatStyle timeStyle) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    final time =
        du.formatTimeAs(TimeOfDay(hour: dt.hour, minute: dt.minute), timeStyle);
    if (diff == 0) return 'Today $time';
    if (diff == 1) return 'Yesterday $time';
    return '${du.formatDateAs(dt, dateStyle)} $time';
  }

  Future<void> _logValue(BuildContext context, WidgetRef ref) async {
    final valueController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Log ${metric.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: valueController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Value',
                  suffixText: metric.unit,
                ),
                validator: (v) {
                  if ((v ?? '').isEmpty) return 'Required';
                  if (double.tryParse(v!) == null) return 'Not a number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
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
      await ref.read(trackerEntriesProvider(metric.id).notifier).add(
            value: double.parse(valueController.text),
            note: noteController.text.trim().isEmpty
                ? null
                : noteController.text.trim(),
          );
    }
  }

  Future<void> _deleteEntry(
      BuildContext context, WidgetRef ref, TrackerEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
            'Remove ${_formatValue(entry.value)}${metric.unit != null ? ' ${metric.unit}' : ''}?'),
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
    if (confirmed == true) {
      await ref
          .read(trackerEntriesProvider(metric.id).notifier)
          .delete(entry.id);
    }
  }

  Future<void> _confirmDeleteMetric(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${metric.name}?'),
        content: const Text(
            'This will remove the metric and all its logged entries.'),
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
      await ref.read(trackerMetricsProvider.notifier).delete(metric.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncEntries = ref.watch(trackerEntriesProvider(metric.id));
    final dateStyle = ref.watch(dateFormatNotifierProvider);
    final timeStyle = ref.watch(timeFormatNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(metric.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete metric',
            onPressed: () => _confirmDeleteMetric(context, ref),
          ),
        ],
      ),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          // entries are sorted desc by recorded_at; for sparkline we want asc
          final sparkValues =
              entries.reversed.map((e) => e.value).toList();
          final latest = entries.isNotEmpty ? entries.first : null;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? colorScheme.surfaceContainerHigh
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            latest != null
                                ? _formatValue(latest.value)
                                : '—',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (metric.unit != null) ...[
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                metric.unit!,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80,
                        child: Sparkline(
                          values: sparkValues,
                          color: colorScheme.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          'No entries yet — tap + to log a value',
                          style: TextStyle(
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          return ListTile(
                            title: Text(
                              metric.unit != null
                                  ? '${_formatValue(e.value)} ${metric.unit}'
                                  : _formatValue(e.value),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              [
                                _formatRecorded(
                                    e.recordedAt, dateStyle, timeStyle),
                                if (e.note != null && e.note!.isNotEmpty)
                                  e.note!,
                              ].join(' · '),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  _deleteEntry(context, ref, e),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_tracker_metric',
        onPressed: () => _logValue(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
