import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/tracker_entry.dart';
import '../models/tracker_metric.dart';
import '../providers/settings_providers.dart';
import '../providers/tracker_providers.dart';
import '../utils/tracker_chart_utils.dart';
import '../utils/date_utils.dart' as du;

class TrackerMetricScreen extends ConsumerStatefulWidget {
  final TrackerMetric metric;
  const TrackerMetricScreen({super.key, required this.metric});

  @override
  ConsumerState<TrackerMetricScreen> createState() =>
      _TrackerMetricScreenState();
}

class _TrackerMetricScreenState extends ConsumerState<TrackerMetricScreen> {
  TrackerMetric get metric => widget.metric;

  TrackerChartType _chartType = TrackerChartType.bar;
  TrackerChartPeriod _chartPeriod = TrackerChartPeriod.daily;
  late DateTime _chartStartDate;
  late DateTime _chartEndDate;
  bool _chartExpanded = true;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _chartEndDate = DateTime(today.year, today.month, today.day);
    _chartStartDate = _chartEndDate.subtract(const Duration(days: 29));
  }

  String _formatValue(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _formatDate(DateTime date, DateFormatStyle dateStyle) =>
      du.formatDateAs(date, dateStyle);

  void _setChartPeriod(TrackerChartPeriod period, List<TrackerEntry> entries) {
    setState(() {
      _chartPeriod = period;
      final range = _defaultRangeForPeriod(period, entries);
      _chartStartDate = range.start;
      _chartEndDate = range.end;
    });
  }

  _ChartDateRange _defaultRangeForPeriod(
    TrackerChartPeriod period,
    List<TrackerEntry> entries,
  ) {
    final today = _dateOnly(DateTime.now());
    final entryDates = entries.map((entry) => _dateOnly(entry.recordedAt));
    final earliestEntry = entryDates.isEmpty
        ? today
        : entryDates.reduce((a, b) => a.isBefore(b) ? a : b);

    switch (period) {
      case TrackerChartPeriod.daily:
        return _ChartDateRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case TrackerChartPeriod.weekly:
        return _ChartDateRange(
          start: _weekStart(today).subtract(const Duration(days: 7 * 11)),
          end: _weekEnd(today),
        );
      case TrackerChartPeriod.monthly:
        return _ChartDateRange(
          start: DateTime(today.year - 1, today.month),
          end: _monthEnd(today),
        );
      case TrackerChartPeriod.yearly:
        return _ChartDateRange(
          start: DateTime(earliestEntry.year),
          end: DateTime(today.year, 12, 31),
        );
    }
  }

  Future<void> _pickChartDate({required bool isStart}) async {
    final current = isStart ? _chartStartDate : _chartEndDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked == null) return;

    final normalized = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (isStart) {
        _chartStartDate = normalized;
        if (_chartStartDate.isAfter(_chartEndDate)) {
          _chartEndDate = _chartStartDate;
        }
      } else {
        _chartEndDate = normalized;
        if (_chartEndDate.isBefore(_chartStartDate)) {
          _chartStartDate = _chartEndDate;
        }
      }
    });
  }

  String _formatRecorded(DateTime dt, DateFormatStyle dateStyle) {
    final recordedDate = DateTime(dt.year, dt.month, dt.day);
    return du.formatDateAs(recordedDate, DateFormatStyle.medium);
  }

  Future<void> _showEntryDialog(
    BuildContext context, {
    TrackerEntry? existing,
  }) async {
    final valueController = TextEditingController(
      text: existing != null ? _formatValue(existing.value) : '',
    );
    final noteController = TextEditingController(text: existing?.note ?? '');
    final formKey = GlobalKey<FormState>();

    final now = DateTime.now();
    final existingDt = existing?.recordedAt.toLocal();
    final existingUtc = existing?.recordedAt;
    final hasExistingTime =
        existingDt != null && (existingDt.hour != 0 || existingDt.minute != 0);

    // Use UTC components for the date so it matches what _formatRecorded displays.
    DateTime selectedDate = existingUtc != null
        ? DateTime(existingUtc.year, existingUtc.month, existingUtc.day)
        : DateTime(now.year, now.month, now.day);
    TimeOfDay? selectedTime = hasExistingTime
        ? TimeOfDay.fromDateTime(existingDt)
        : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final dateStyle = ref.read(dateFormatNotifierProvider);

          String displayDate() {
            final today = DateTime(now.year, now.month, now.day);
            final diff = today.difference(selectedDate).inDays;
            if (diff == 0) return 'Today';
            if (diff == 1) return 'Yesterday';
            return du.formatDateAs(selectedDate, dateStyle);
          }

          return AlertDialog(
            title: Text(existing != null ? 'Edit entry' : 'Log ${metric.name}'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: valueController,
                    autofocus: existing == null,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
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
                  // Date row
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => selectedDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(displayDate()),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Time toggle
                  Row(
                    children: [
                      Text(
                        'Add time',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      Switch(
                        value: selectedTime != null,
                        onChanged: (on) async {
                          if (on) {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.now(),
                            );
                            setState(() => selectedTime = picked);
                          } else {
                            setState(() => selectedTime = null);
                          }
                        },
                      ),
                      if (selectedTime != null)
                        TextButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: selectedTime!,
                            );
                            if (picked != null) {
                              setState(() => selectedTime = picked);
                            }
                          },
                          child: Text(selectedTime!.format(ctx)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
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
          );
        },
      ),
    );

    if (saved == true) {
      final recordedAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime?.hour ?? 0,
        selectedTime?.minute ?? 0,
      );
      final value = double.parse(valueController.text);
      final note = noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim();
      final notifier = ref.read(trackerEntriesProvider(metric.id).notifier);

      if (existing != null) {
        await notifier.editEntry(
          existing.id,
          value: value,
          note: note,
          clearNote: note == null && existing.note != null,
          recordedAt: recordedAt,
        );
      } else {
        await notifier.add(value: value, note: note, recordedAt: recordedAt);
      }
    }
  }

  Future<void> _deleteEntry(BuildContext context, TrackerEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Remove ${_formatValue(entry.value)}${metric.unit != null ? ' ${metric.unit}' : ''}?',
        ),
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

  Future<void> _confirmDeleteMetric(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${metric.name}?'),
        content: const Text(
          'This will remove the metric and all its logged entries.',
        ),
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

  Future<void> _editMetric(BuildContext context) async {
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

  Future<void> _exportCsv(
    BuildContext context,
    List<TrackerEntry> entries,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln('recorded_at,value,note');
    for (final e in entries) {
      final ts = e.recordedAt.toLocal().toIso8601String();
      final val = _formatValue(e.value);
      final note = (e.note ?? '').replaceAll('"', '""');
      buffer.writeln('$ts,$val,"$note"');
    }
    final csvContent = buffer.toString();
    final safeName = metric.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    if (Platform.isMacOS) {
      final location = await getSaveLocation(
        suggestedName: '${safeName}_export.csv',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsString(csvContent);
    } else {
      final dir = await getTemporaryDirectory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/${safeName}_export.csv');
      await file.writeAsString(csvContent);
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: '${metric.name} export',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncEntries = ref.watch(trackerEntriesProvider(metric.id));
    final dateStyle = ref.watch(dateFormatNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(metric.name),
        actions: [
          asyncEntries.maybeWhen(
            data: (entries) => entries.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Export CSV',
                    onPressed: () => _exportCsv(context, entries),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit metric',
            onPressed: () => _editMetric(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete metric',
            onPressed: () => _confirmDeleteMetric(context),
          ),
        ],
      ),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          final chartPoints = buildTrackerChartPoints(
            entries: entries,
            startDate: _chartStartDate,
            endDate: _chartEndDate,
            period: _chartPeriod,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _TrackerChartPanel(
                  chartType: _chartType,
                  period: _chartPeriod,
                  points: chartPoints,
                  unit: metric.unit,
                  startDate: _chartStartDate,
                  endDate: _chartEndDate,
                  formatValue: _formatValue,
                  formatDate: (date) => _formatDate(date, dateStyle),
                  onChartTypeChanged: (value) {
                    setState(() => _chartType = value);
                  },
                  onPeriodChanged: (value) => _setChartPeriod(value, entries),
                  onPickStart: () => _pickChartDate(isStart: true),
                  onPickEnd: () => _pickChartDate(isStart: false),
                  expanded: _chartExpanded,
                  onToggleExpanded: () =>
                      setState(() => _chartExpanded = !_chartExpanded),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          'No entries yet — tap + to log a value',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          return _TrackerEntryRow(
                            entry: e,
                            unit: metric.unit,
                            formatValue: _formatValue,
                            formatRecorded: (date) =>
                                _formatRecorded(date, dateStyle),
                            onEdit: () =>
                                _showEntryDialog(context, existing: e),
                            onDelete: () => _deleteEntry(context, e),
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
        onPressed: () => _showEntryDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ChartDateRange {
  final DateTime start;
  final DateTime end;

  const _ChartDateRange({required this.start, required this.end});
}

class _TrackerEntryRow extends StatelessWidget {
  final TrackerEntry entry;
  final String? unit;
  final String Function(double value) formatValue;
  final String Function(DateTime date) formatRecorded;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TrackerEntryRow({
    required this.entry,
    required this.unit,
    required this.formatValue,
    required this.formatRecorded,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final valueText = unit == null
        ? formatValue(entry.value)
        : '${formatValue(entry.value)} $unit';

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatRecorded(entry.recordedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.76),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    valueText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (entry.note != null && entry.note!.isNotEmpty) ...[
                    Text(
                      ' · ${entry.note!}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<_EntryAction>(
              tooltip: 'Entry actions',
              onSelected: (action) {
                switch (action) {
                  case _EntryAction.edit:
                    onEdit();
                  case _EntryAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _EntryAction.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _EntryAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum TrackerChartType { line, bar }

class _TrackerChartPanel extends StatelessWidget {
  final TrackerChartType chartType;
  final TrackerChartPeriod period;
  final List<TrackerChartPoint> points;
  final String? unit;
  final DateTime startDate;
  final DateTime endDate;
  final String Function(double value) formatValue;
  final String Function(DateTime date) formatDate;
  final ValueChanged<TrackerChartType> onChartTypeChanged;
  final ValueChanged<TrackerChartPeriod> onPeriodChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const _TrackerChartPanel({
    required this.chartType,
    required this.period,
    required this.points,
    required this.unit,
    required this.startDate,
    required this.endDate,
    required this.formatValue,
    required this.formatDate,
    required this.onChartTypeChanged,
    required this.onPeriodChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.expanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasRangeValue = points.any((point) => point.value != 0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<TrackerChartType>(
                        style: _compactSegmentedStyle(),
                        segments: const [
                          ButtonSegment(
                            value: TrackerChartType.line,
                            icon: Icon(Icons.show_chart, size: 18),
                            label: Text('Line'),
                          ),
                          ButtonSegment(
                            value: TrackerChartType.bar,
                            icon: Icon(Icons.bar_chart, size: 18),
                            label: Text('Bar'),
                          ),
                        ],
                        selected: {chartType},
                        onSelectionChanged: (selection) {
                          onChartTypeChanged(selection.first);
                        },
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<TrackerChartPeriod>(
                        style: _compactSegmentedStyle(),
                        segments: const [
                          ButtonSegment(
                            value: TrackerChartPeriod.daily,
                            label: Text('Daily'),
                          ),
                          ButtonSegment(
                            value: TrackerChartPeriod.weekly,
                            label: Text('Weekly'),
                          ),
                          ButtonSegment(
                            value: TrackerChartPeriod.monthly,
                            label: Text('Monthly'),
                          ),
                          ButtonSegment(
                            value: TrackerChartPeriod.yearly,
                            label: Text('Yearly'),
                          ),
                        ],
                        selected: {period},
                        onSelectionChanged: (selection) {
                          onPeriodChanged(selection.first);
                        },
                      ),
                      const SizedBox(width: 8),
                      _ChartDateButton(
                        label: 'Start',
                        value: formatDate(startDate),
                        onPressed: onPickStart,
                      ),
                      const SizedBox(width: 8),
                      _ChartDateButton(
                        label: 'End',
                        value: formatDate(endDate),
                        onPressed: onPickEnd,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                ),
                tooltip: expanded ? 'Hide chart' : 'Show chart',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleExpanded,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 260,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final minimumChartWidth =
                                points.length *
                                (chartType == TrackerChartType.bar ? 30 : 36);
                            final chartWidth =
                                minimumChartWidth > constraints.maxWidth
                                    ? minimumChartWidth.toDouble()
                                    : constraints.maxWidth;

                            return Stack(
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: chartWidth,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        right: 4,
                                      ),
                                      child: chartType == TrackerChartType.line
                                          ? _TrackerLineChart(
                                              points: points,
                                              period: period,
                                              unit: unit,
                                              color: colorScheme.primary,
                                              labelColor:
                                                  colorScheme.onSurfaceVariant,
                                              gridColor: colorScheme
                                                  .outlineVariant
                                                  .withValues(alpha: 0.7),
                                              tooltipColor:
                                                  colorScheme.inverseSurface,
                                              tooltipTextColor:
                                                  colorScheme.onInverseSurface,
                                              formatValue: formatValue,
                                              formatDate: formatDate,
                                            )
                                          : _TrackerBarChart(
                                              points: points,
                                              period: period,
                                              color: colorScheme.primary,
                                              labelColor:
                                                  colorScheme.onSurfaceVariant,
                                              gridColor: colorScheme
                                                  .outlineVariant
                                                  .withValues(alpha: 0.7),
                                              tooltipColor:
                                                  colorScheme.inverseSurface,
                                              tooltipTextColor:
                                                  colorScheme.onInverseSurface,
                                              formatValue: formatValue,
                                              formatDate: formatDate,
                                            ),
                                    ),
                                  ),
                                ),
                                if (!hasRangeValue)
                                  Center(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: colorScheme.surface
                                            .withValues(alpha: 0.92),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          'No entries in this range',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_periodLabel(period)} totals · ${formatDate(startDate)} to ${formatDate(endDate)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  ButtonStyle _compactSegmentedStyle() {
    return ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 10),
      ),
      textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
    );
  }

  String _periodLabel(TrackerChartPeriod period) {
    switch (period) {
      case TrackerChartPeriod.daily:
        return 'Daily';
      case TrackerChartPeriod.weekly:
        return 'Weekly';
      case TrackerChartPeriod.monthly:
        return 'Monthly';
      case TrackerChartPeriod.yearly:
        return 'Yearly';
    }
  }
}

class _ChartDateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onPressed;

  const _ChartDateButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value),
        ],
      ),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _TrackerLineChart extends StatelessWidget {
  final List<TrackerChartPoint> points;
  final TrackerChartPeriod period;
  final String? unit;
  final Color color;
  final Color labelColor;
  final Color gridColor;
  final Color tooltipColor;
  final Color tooltipTextColor;
  final String Function(double value) formatValue;
  final String Function(DateTime date) formatDate;

  const _TrackerLineChart({
    required this.points,
    required this.period,
    required this.unit,
    required this.color,
    required this.labelColor,
    required this.gridColor,
    required this.tooltipColor,
    required this.tooltipTextColor,
    required this.formatValue,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = _chartMaxY(points);
    final yInterval = _niceInterval(maxY);
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).clamp(0, points.length).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: gridColor),
            bottom: BorderSide(color: gridColor),
          ),
        ),
        titlesData: _titlesData(
          points: points,
          period: period,
          labelColor: labelColor,
          maxY: maxY,
          yInterval: yInterval,
          formatDate: formatDate,
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => tooltipColor,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => spots.map((spot) {
              final point = points[spot.x.round()];
              return LineTooltipItem(
                '${_pointLabel(point, period, formatDate)}\n${formatValue(point.value)}${unit != null ? ' $unit' : ''}',
                TextStyle(color: tooltipTextColor, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
            dotData: FlDotData(show: points.length <= 16),
          ),
        ],
      ),
    );
  }
}

class _TrackerBarChart extends StatelessWidget {
  final List<TrackerChartPoint> points;
  final TrackerChartPeriod period;
  final Color color;
  final Color labelColor;
  final Color gridColor;
  final Color tooltipColor;
  final Color tooltipTextColor;
  final String Function(double value) formatValue;
  final String Function(DateTime date) formatDate;

  const _TrackerBarChart({
    required this.points,
    required this.period,
    required this.color,
    required this.labelColor,
    required this.gridColor,
    required this.tooltipColor,
    required this.tooltipTextColor,
    required this.formatValue,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = _chartMaxY(points);
    final yInterval = _niceInterval(maxY);
    final barWidth = _barWidth(points.length);
    final showTopLabels = points.length <= 40;

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceEvenly,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: gridColor),
            bottom: BorderSide(color: gridColor),
          ),
        ),
        titlesData: _titlesData(
          points: points,
          period: period,
          labelColor: labelColor,
          maxY: maxY,
          yInterval: yInterval,
          formatDate: formatDate,
          topLabelGetter: showTopLabels
              ? (i) => points[i].value > 0 ? formatValue(points[i].value) : ''
              : null,
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => tooltipColor,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (group.x < 0 || group.x >= points.length) return null;
              final point = points[group.x];
              if (point.value <= 0) return null;
              return BarTooltipItem(
                '${_shortPointLabel(point, period, formatDate)}\n${formatValue(point.value)}',
                TextStyle(
                  color: tooltipTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              showingTooltipIndicators: const [],
              barRods: [
                BarChartRodData(
                  toY: points[i].value,
                  width: barWidth,
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

FlTitlesData _titlesData({
  required List<TrackerChartPoint> points,
  required TrackerChartPeriod period,
  required Color labelColor,
  required double maxY,
  required double yInterval,
  required String Function(DateTime date) formatDate,
  String Function(int index)? topLabelGetter,
}) {
  final labelStyle = TextStyle(
    color: labelColor,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  return FlTitlesData(
    topTitles: topLabelGetter == null
        ? const AxisTitles()
        : AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 ||
                    index >= points.length ||
                    value != index.toDouble()) {
                  return const SizedBox.shrink();
                }
                final text = topLabelGetter(index);
                if (text.isEmpty) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  angle: text.length > 2 ? -math.pi / 4 : 0.0,
                  space: 2,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(
                    meta,
                    enabled: false,
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                );
              },
            ),
          ),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 48,
        interval: yInterval,
        getTitlesWidget: (value, meta) {
          if (value == 0 || value > maxY) {
            return const SizedBox.shrink();
          }
          return Text(value.round().toString(), style: labelStyle);
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        // Space is measured from the axis to the top of the label's layout
        // box (text height ~14px).  At –45° a label like "02 APR 2026"
        // (~65px wide) extends ~23px upward past its layout top, so we need
        // space ≥ 23px to keep it from overlapping the chart area.
        reservedSize: 80,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if (index < 0 || index >= points.length || value != index) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            angle: -math.pi / 4,
            space: 24,
            fitInside: SideTitleFitInsideData.fromTitleMeta(
              meta,
              enabled: false,
            ),
            child: Text(
              _shortPointLabel(points[index], period, formatDate),
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          );
        },
      ),
    ),
  );
}

double _chartMaxY(List<TrackerChartPoint> points) {
  final maxValue = points.fold<double>(
    0,
    (m, p) => p.value > m ? p.value : m,
  );
  if (maxValue <= 0) return 5;
  final interval = _niceInterval(maxValue * 1.1);
  return ((maxValue * 1.1) / interval).ceil() * interval;
}

// Returns a "nice" grid interval for a given data range (targeting ~5 steps).
double _niceInterval(double range) {
  if (range <= 0) return 1;
  final raw = range / 5;
  if (raw < 1) return 1;
  final magnitude =
      math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final residual = raw / magnitude;
  final double nice;
  if (residual <= 1) {
    nice = 1;
  } else if (residual <= 2) {
    nice = 2;
  } else if (residual <= 5) {
    nice = 5;
  } else {
    nice = 10;
  }
  return nice * magnitude;
}

double _barWidth(int pointCount) {
  if (pointCount > 40) return 5;
  if (pointCount > 24) return 8;
  return 10;
}

String _pointLabel(
  TrackerChartPoint point,
  TrackerChartPeriod period,
  String Function(DateTime date) formatDate,
) {
  if (period == TrackerChartPeriod.daily || point.start == point.end) {
    return formatDate(point.start);
  }
  return '${formatDate(point.start)} - ${formatDate(point.end)}';
}

String _shortPointLabel(
  TrackerChartPoint point,
  TrackerChartPeriod period,
  String Function(DateTime date) formatDate,
) {
  final d = point.start;
  switch (period) {
    case TrackerChartPeriod.daily:
    case TrackerChartPeriod.weekly:
      return '${d.day.toString().padLeft(2, '0')} ${_monthAbbr(d.month)} ${d.year}';
    case TrackerChartPeriod.monthly:
      return '${_monthAbbr(d.month)} ${d.year}';
    case TrackerChartPeriod.yearly:
      return d.year.toString();
  }
}

const _monthAbbrs = [
  '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

String _monthAbbr(int month) => _monthAbbrs[month.clamp(1, 12)];

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _weekStart(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + 1);

DateTime _weekEnd(DateTime date) =>
    _weekStart(date).add(const Duration(days: 6));

DateTime _monthEnd(DateTime date) => DateTime(date.year, date.month + 1, 0);

enum _EntryAction { edit, delete }
