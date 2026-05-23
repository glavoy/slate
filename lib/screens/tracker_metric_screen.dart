import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/tracker_entry.dart';
import '../models/tracker_metric.dart';
import '../providers/settings_providers.dart';
import '../providers/tracker_providers.dart';
import '../utils/date_utils.dart' as du;
import '../widgets/sparkline.dart';

class TrackerMetricScreen extends ConsumerStatefulWidget {
  final TrackerMetric metric;
  const TrackerMetricScreen({super.key, required this.metric});

  @override
  ConsumerState<TrackerMetricScreen> createState() =>
      _TrackerMetricScreenState();
}

class _TrackerMetricScreenState extends ConsumerState<TrackerMetricScreen> {
  TrackerMetric get metric => widget.metric;

  String _formatValue(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _formatRecorded(
      DateTime dt, DateFormatStyle dateStyle, TimeFormatStyle timeStyle) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diff = today.difference(target).inDays;
    final hasTime = local.hour != 0 || local.minute != 0;
    final datePart = diff == 0
        ? 'Today'
        : diff == 1
            ? 'Yesterday'
            : du.formatDateAs(local, dateStyle);
    if (!hasTime) return datePart;
    final timePart = du.formatTimeAs(
        TimeOfDay(hour: local.hour, minute: local.minute), timeStyle);
    return '$datePart $timePart';
  }

  Future<void> _showEntryDialog(BuildContext context,
      {TrackerEntry? existing}) async {
    final valueController =
        TextEditingController(text: existing != null ? _formatValue(existing.value) : '');
    final noteController =
        TextEditingController(text: existing?.note ?? '');
    final formKey = GlobalKey<FormState>();

    final now = DateTime.now();
    final existingDt = existing?.recordedAt.toLocal();
    final hasExistingTime = existingDt != null &&
        (existingDt.hour != 0 || existingDt.minute != 0);

    DateTime selectedDate = existingDt != null
        ? DateTime(existingDt.year, existingDt.month, existingDt.day)
        : DateTime(now.year, now.month, now.day);
    TimeOfDay? selectedTime =
        hasExistingTime ? TimeOfDay.fromDateTime(existingDt) : null;

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
                      Text('Add time',
                          style: Theme.of(ctx).textTheme.bodySmall),
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
                    decoration:
                        const InputDecoration(labelText: 'Note (optional)'),
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
      final note =
          noteController.text.trim().isEmpty ? null : noteController.text.trim();
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

  Future<void> _deleteEntry(
      BuildContext context, TrackerEntry entry) async {
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

  Future<void> _confirmDeleteMetric(BuildContext context) async {
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final newUnit = unitController.text.trim().isEmpty
          ? null
          : unitController.text.trim();
      await ref.read(trackerMetricsProvider.notifier).editMetric(
            metric.id,
            name: nameController.text.trim(),
            unit: newUnit,
            clearUnit: newUnit == null && metric.unit != null,
          );
    }
  }

  Future<void> _exportCsv(
      BuildContext context, List<TrackerEntry> entries) async {
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
    final timeStyle = ref.watch(timeFormatNotifierProvider);

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
                            trailing: PopupMenuButton<_EntryAction>(
                              onSelected: (action) {
                                switch (action) {
                                  case _EntryAction.edit:
                                    _showEntryDialog(context, existing: e);
                                  case _EntryAction.delete:
                                    _deleteEntry(context, e);
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
                                    leading: Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    title: Text('Delete',
                                        style:
                                            TextStyle(color: Colors.red)),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
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
        onPressed: () => _showEntryDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

enum _EntryAction { edit, delete }
