import 'package:flutter/material.dart';

import '../providers/settings_providers.dart';
import '../utils/date_utils.dart' as du;

/// Change this value to tune the tracker entry dialog's fixed date-control width.
const double trackerEntryDateControlWidth = 300;

/// A compact date selector for tracker entries.
///
/// It keeps date navigation within the range from 1 January 2000 through
/// today, matching the tracker entry date picker rules.
class TrackerEntryDatePicker extends StatelessWidget {
  final DateTime selectedDate;
  final DateTime today;
  final DateFormatStyle dateStyle;
  final ValueChanged<DateTime> onDateChanged;

  const TrackerEntryDatePicker({
    super.key,
    required this.selectedDate,
    required this.today,
    required this.dateStyle,
    required this.onDateChanged,
  });

  String _displayDate() {
    final difference = today.difference(selectedDate).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return du.formatDateAs(selectedDate, dateStyle);
  }

  @override
  Widget build(BuildContext context) {
    final firstDate = DateTime(2000);
    final canMoveBackward = selectedDate.isAfter(firstDate);
    final canMoveForward = selectedDate.isBefore(today);

    return SizedBox(
      width: trackerEntryDateControlWidth,
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date'),
        child: Row(
          children: [
            IconButton(
              key: const Key('tracker_entry_previous_date'),
              tooltip: 'Previous day',
              onPressed: canMoveBackward
                  ? () => onDateChanged(
                      DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day - 1,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton.icon(
                key: const Key('tracker_entry_calendar_date'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: firstDate,
                    lastDate: today,
                  );
                  if (picked != null) {
                    onDateChanged(
                      DateTime(picked.year, picked.month, picked.day),
                    );
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_displayDate()),
              ),
            ),
            IconButton(
              key: const Key('tracker_entry_next_date'),
              tooltip: 'Next day',
              onPressed: canMoveForward
                  ? () => onDateChanged(
                      DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day + 1,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              key: const Key('tracker_entry_today_date'),
              onPressed: canMoveForward ? () => onDateChanged(today) : null,
              child: const Text('Today'),
            ),
          ],
        ),
      ),
    );
  }
}
