import 'package:home_management/src/features/household/domain/household.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:home_management/src/core/domain/roles.dart';

abstract interface class HouseholdRepository {
  Future<Household?> current();
  Future<void> create({
    required String name,
    required String currencyCode,
    required String timeZone,
  });
  Future<List<HouseholdMember>> members(String householdId);
  Future<void> updateMemberRole({
    required String householdId,
    required String userId,
    required HouseholdRole role,
  });
  Future<void> removeMember({
    required String householdId,
    required String userId,
  });
}

final class SupabaseHouseholdRepository implements HouseholdRepository {
  const SupabaseHouseholdRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Household?> current() async {
    final invitation = Uri.base.queryParameters['invite'];
    if (invitation != null && invitation.isNotEmpty) {
      await _client.rpc<String>('accept_household_invitation',
          params: {'p_token': invitation});
    }
    final result = await _client.from('my_households').select().maybeSingle();
    return result == null ? null : Household.fromJson(result);
  }

  @override
  Future<void> create({
    required String name,
    required String currencyCode,
    required String timeZone,
  }) async {
    await _client.rpc<void>(
      'create_household',
      params: {
        'household_name': name,
        'currency': currencyCode,
        'timezone': timeZone,
      },
    );
  }

  @override
  Future<List<HouseholdMember>> members(String householdId) async {
    final rows = await _client
        .from('memberships')
        .select('user_id, role, profiles!inner(display_name)')
        .eq('household_id', householdId)
        .order('joined_at');
    return rows.map((row) {
      final profile = row['profiles'] as Map<String, dynamic>;
      return HouseholdMember(
        userId: row['user_id'] as String,
        displayName: profile['display_name'] as String,
        role: HouseholdRole.values.byName(row['role'] as String),
      );
    }).toList();
  }

  @override
  Future<void> updateMemberRole({
    required String householdId,
    required String userId,
    required HouseholdRole role,
  }) async {
    await _client
        .from('memberships')
        .update({'role': role.name})
        .eq('household_id', householdId)
        .eq('user_id', userId);
  }

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) async {
    await _client
        .from('memberships')
        .delete()
        .eq('household_id', householdId)
        .eq('user_id', userId);
  }
}
