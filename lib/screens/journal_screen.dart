import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../providers/supabase_provider.dart';
import '../utils/date_utils.dart' as du;

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final _todayController = TextEditingController();
  Timer? _debounce;
  String _lastSavedToday = '';
  bool _todayInitialized = false;
  String? _expandedEntryId;

  static const _debounceDuration = Duration(milliseconds: 1200);

  @override
  void dispose() {
    _debounce?.cancel();
    _flushTodayIfDirty();
    _todayController.dispose();
    super.dispose();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _flushTodayIfDirty() {
    if (!_todayInitialized) return;
    final value = _todayController.text;
    if (value == _lastSavedToday) return;
    _lastSavedToday = value;
    ref.read(journalEntriesProvider.notifier).save(_today, value);
  }

  void _scheduleTodaySave() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flushTodayIfDirty);
  }

  @override
  Widget build(BuildContext context) {
    final asyncEntries = ref.watch(journalEntriesProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Journal',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: const [],
      ),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          // Find today's entry, if any
          final todayKey = _today;
          JournalEntry? todayEntry;
          final past = <JournalEntry>[];
          for (final e in entries) {
            final ed = DateTime(
                e.entryDate.year, e.entryDate.month, e.entryDate.day);
            if (ed == todayKey) {
              todayEntry = e;
            } else {
              past.add(e);
            }
          }
          if (!_todayInitialized) {
            _todayController.text = todayEntry?.content ?? '';
            _lastSavedToday = todayEntry?.content ?? '';
            _todayInitialized = true;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              _todayCard(theme, colorScheme),
              if (past.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    'PREVIOUS',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ...past.map((e) => _pastEntryCard(e, theme, colorScheme)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _todayCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today · ${du.formatDateGroupHeader(_today)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _todayController,
            maxLines: null,
            minLines: 4,
            keyboardType: TextInputType.multiline,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: "What's on your mind today?",
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => _scheduleTodaySave(),
          ),
        ],
      ),
    );
  }

  Widget _pastEntryCard(
      JournalEntry entry, ThemeData theme, ColorScheme colorScheme) {
    final isExpanded = _expandedEntryId == entry.id;
    final preview = () {
      final raw = entry.content.trim();
      if (raw.isEmpty) return '(empty)';
      final firstLine = raw.split('\n').first;
      return firstLine.length > 80
          ? '${firstLine.substring(0, 80)}…'
          : firstLine;
    }();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: theme.brightness == Brightness.dark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _expandedEntryId = isExpanded ? null : entry.id;
          }),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        du.formatDateGroupHeader(entry.entryDate),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface
                              .withValues(alpha: 0.65),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (!isExpanded)
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  )
                else
                  _ExpandedPastEntry(entry: entry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedPastEntry extends ConsumerStatefulWidget {
  final JournalEntry entry;
  const _ExpandedPastEntry({required this.entry});

  @override
  ConsumerState<_ExpandedPastEntry> createState() =>
      _ExpandedPastEntryState();
}

class _ExpandedPastEntryState extends ConsumerState<_ExpandedPastEntry> {
  late final TextEditingController _controller;
  Timer? _debounce;
  String _lastSaved = '';

  static const _debounceDuration = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entry.content);
    _lastSaved = widget.entry.content;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flush();
    _controller.dispose();
    super.dispose();
  }

  void _flush() {
    if (_controller.text == _lastSaved) return;
    _lastSaved = _controller.text;
    ref
        .read(journalEntriesProvider.notifier)
        .save(widget.entry.entryDate, _controller.text);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _flush);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: theme.textTheme.bodyMedium,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (_) => _schedule(),
    );
  }
}
