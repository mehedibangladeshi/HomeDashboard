import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class CalendarRepository {
  Future<List<Map<String, dynamic>>> events(String householdId);
  Future<void> createEvent({
    required String householdId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
  });
}

final class SupabaseCalendarRepository implements CalendarRepository {
  const SupabaseCalendarRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> events(String householdId) async {
    final cacheKey =
        'household_events_${householdId}_${_client.auth.currentUser!.id}';
    final preferences = await SharedPreferences.getInstance();
    try {
      final rows = await _client
          .from('household_events')
          .select()
          .eq('household_id', householdId)
          .neq('status', 'cancelled')
          .gte(
            'ends_at',
            DateTime.now()
                .subtract(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
          )
          .order('starts_at')
          .limit(100);
      await preferences.setString(cacheKey, jsonEncode(rows));
      return List<Map<String, dynamic>>.from(rows);
    } catch (error) {
      if (error is PostgrestException || error is AuthException) rethrow;
      final cached = preferences.getString(cacheKey);
      if (cached == null) rethrow;
      return (jsonDecode(cached) as List).cast<Map<String, dynamic>>();
    }
  }

  @override
  Future<void> createEvent({
    required String householdId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    await _client.from('household_events').insert({
      'household_id': householdId,
      'title': title,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'created_by': _client.auth.currentUser!.id,
    });
  }
}
