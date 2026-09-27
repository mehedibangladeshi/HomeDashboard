import 'dart:convert';

import 'package:home_management/src/features/chores/domain/chore.dart';
import 'package:home_management/src/core/domain/roles.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ChoreRepository {
  Future<List<ChoreOccurrence>> upcoming(String householdId);
  Future<void> complete(String occurrenceId);
  Future<void> create({
    required String householdId,
    required String title,
    required String assigneeUserId,
    required ChoreFrequency frequency,
    required DateTime startsAt,
  });
}

final class SupabaseChoreRepository implements ChoreRepository {
  const SupabaseChoreRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ChoreOccurrence>> upcoming(String householdId) async {
    final cacheKey =
        'chore_occurrences_${householdId}_${_client.auth.currentUser!.id}';
    final preferences = await SharedPreferences.getInstance();
    List<dynamic> rows;
    try {
      rows = await _client
          .from('chore_occurrences')
          .select(
            'id, chore_id, title_snapshot, assignee_user_id, due_at, completed_at',
          )
          .eq('household_id', householdId)
          .eq('status', 'scheduled')
          .order('due_at')
          .limit(100);
      await preferences.setString(cacheKey, jsonEncode(rows));
    } catch (error) {
      if (error is PostgrestException || error is AuthException) rethrow;
      final cached = preferences.getString(cacheKey);
      if (cached == null) rethrow;
      rows = jsonDecode(cached) as List;
    }
    return rows
        .cast<Map<String, dynamic>>()
        .map(
          (row) => ChoreOccurrence(
            id: row['id'] as String,
            choreId: row['chore_id'] as String,
            title: row['title_snapshot'] as String,
            assigneeUserId: row['assignee_user_id'] as String,
            dueAt: DateTime.parse(row['due_at'] as String).toLocal(),
            completedAt: row['completed_at'] == null
                ? null
                : DateTime.parse(row['completed_at'] as String).toLocal(),
          ),
        )
        .toList();
  }

  @override
  Future<void> complete(String occurrenceId) async {
    await _client.rpc<void>(
      'complete_chore',
      params: {'p_occurrence_id': occurrenceId},
    );
  }

  @override
  Future<void> create({
    required String householdId,
    required String title,
    required String assigneeUserId,
    required ChoreFrequency frequency,
    required DateTime startsAt,
  }) async {
    await _client.rpc<void>(
      'create_chore',
      params: {
        'p_household_id': householdId,
        'p_title': title,
        'p_description': null,
        'p_assignee_user_id': assigneeUserId,
        'p_frequency': frequency.name,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
      },
    );
  }
}
