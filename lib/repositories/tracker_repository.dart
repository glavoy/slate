import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tracker_metric.dart';
import '../models/tracker_entry.dart';

class TrackerRepository {
  TrackerRepository(this._client);
  final SupabaseClient _client;

  // ── Metrics ───────────────────────────────────────────────────────────
  Future<List<TrackerMetric>> fetchMetrics() async {
    final rows = await _client
        .from('tracker_metrics')
        .select()
        .order('created_at', ascending: true);
    return rows
        .map<TrackerMetric>((r) => TrackerMetric.fromJson(r))
        .toList();
  }

  Future<TrackerMetric> createMetric({
    required String name,
    String? unit,
  }) async {
    final inserted = await _client
        .from('tracker_metrics')
        .insert({
          'name': name,
          if (unit != null && unit.isNotEmpty) 'unit': unit,
        })
        .select()
        .single();
    return TrackerMetric.fromJson(inserted);
  }

  Future<void> deleteMetric(String id) async {
    await _client.from('tracker_metrics').delete().eq('id', id);
  }

  // ── Entries ───────────────────────────────────────────────────────────
  Future<List<TrackerEntry>> fetchEntries(String metricId,
      {int? limit}) async {
    var query = _client
        .from('tracker_entries')
        .select()
        .eq('metric_id', metricId)
        .order('recorded_at', ascending: false);
    final rows = limit != null ? await query.limit(limit) : await query;
    return rows
        .map<TrackerEntry>((r) => TrackerEntry.fromJson(r))
        .toList();
  }

  Future<TrackerEntry> addEntry({
    required String metricId,
    required double value,
    String? note,
    DateTime? recordedAt,
  }) async {
    final inserted = await _client
        .from('tracker_entries')
        .insert({
          'metric_id': metricId,
          'value': value,
          if (note != null && note.isNotEmpty) 'note': note,
          if (recordedAt != null)
            'recorded_at': recordedAt.toIso8601String(),
        })
        .select()
        .single();
    return TrackerEntry.fromJson(inserted);
  }

  Future<void> deleteEntry(String id) async {
    await _client.from('tracker_entries').delete().eq('id', id);
  }
}
