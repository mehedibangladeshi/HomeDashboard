import 'dart:convert';
import 'dart:typed_data';

import 'package:home_management/src/core/domain/roles.dart';
import 'package:home_management/src/features/spending/domain/expense.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SpendingRepository {
  Future<List<Map<String, dynamic>>> recent(String householdId);
  Future<String> createPurchase(NewPurchase purchase, HouseholdRole role);
  Future<void> attachReceipt(
    String expenseId,
    String householdId,
    List<int> bytes,
  );
  Future<void> approve(String expenseId);
  Future<void> reject(String expenseId, String reason);
  Future<Map<String, dynamic>> detail(String expenseId);
  Future<String> receiptUrl(String path);
  Future<void> voidExpense(String expenseId, String reason);
  Future<void> correctExpense(Map<String, dynamic> original, String summary,
      int amountMinor, String reason);
  Future<List<Map<String, dynamic>>> analytics(
    String householdId,
    DateTime from,
    DateTime until,
  );
  Future<List<Map<String, dynamic>>> categories(String householdId);
  Future<List<Map<String, dynamic>>> budgets(String householdId);
  Future<List<Map<String, dynamic>>> obligations(String householdId);
  Future<void> setBudget({
    required String householdId,
    required String categoryId,
    required DateTime month,
    required int amountMinor,
  });
  Future<void> createObligation({
    required String householdId,
    required String title,
    required int expectedAmountMinor,
    required String categoryId,
    required String frequency,
    required DateTime startsOn,
  });
}

final class SupabaseSpendingRepository implements SpendingRepository {
  const SupabaseSpendingRepository(this._client, {this.cacheRole = 'unknown'});

  final SupabaseClient _client;
  final String cacheRole;

  @override
  Future<Map<String, dynamic>> detail(String expenseId) => _client
      .from('expenses')
      .select('*, expense_items(*)')
      .eq('id', expenseId)
      .single();

  @override
  Future<String> receiptUrl(String path) =>
      _client.storage.from('receipts').createSignedUrl(path, 60);

  @override
  Future<void> voidExpense(String expenseId, String reason) async {
    await _client.rpc<void>('void_expense',
        params: {'p_expense_id': expenseId, 'p_reason': reason});
  }

  @override
  Future<void> correctExpense(Map<String, dynamic> original, String summary,
      int amountMinor, String reason) async {
    await _client.rpc<int>('correct_expense', params: {
      'p_expense_id': original['id'],
      'p_expected_version': original['version'],
      'p_summary': summary,
      'p_total_minor': amountMinor,
      'p_incurred_at': original['incurred_at'],
      'p_category_id': original['category_id'],
      'p_payment_source_id': original['payment_source_id'],
      'p_reason': reason,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> recent(String householdId) async {
    final cacheKey =
        'recent_expenses_${householdId}_${_client.auth.currentUser!.id}_$cacheRole';
    final preferences = await SharedPreferences.getInstance();
    try {
      final rows = await _client
          .from('expenses')
          .select(
              'id, summary, total_minor, currency_code, incurred_at, status')
          .eq('household_id', householdId)
          .order('incurred_at', ascending: false)
          .limit(50);
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
  Future<String> createPurchase(
    NewPurchase purchase,
    HouseholdRole role,
  ) async {
    purchase.validate();
    return _client.rpc<String>(
      'create_purchase',
      params: {
        'p_client_mutation_id': purchase.clientMutationId,
        'p_household_id': purchase.householdId,
        'p_summary': purchase.summary.trim(),
        'p_total_minor': purchase.totalMinor,
        'p_currency_code': purchase.currencyCode,
        'p_incurred_at': purchase.incurredAt.toUtc().toIso8601String(),
        'p_payer_user_id': purchase.payerUserId,
        'p_category_id': purchase.categoryId,
        'p_payment_source_id': purchase.paymentSourceId,
        'p_note': purchase.note,
        'p_items': purchase.items
            .map(
              (item) => {
                'name': item.name,
                'amount_minor': item.amountMinor,
                'category_id': item.categoryId,
              },
            )
            .toList(),
      },
    );
  }

  @override
  Future<void> attachReceipt(
    String expenseId,
    String householdId,
    List<int> bytes,
  ) async {
    final path = '$householdId/$expenseId.jpg';
    await _client.storage.from('receipts').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    await _client.rpc<void>(
      'attach_expense_receipt',
      params: {
        'p_expense_id': expenseId,
        'p_receipt_path': path,
      },
    );
  }

  @override
  Future<void> approve(String expenseId) async {
    await _client.rpc<void>(
      'review_expense',
      params: {
        'p_expense_id': expenseId,
        'p_decision': 'approved',
        'p_reason': null,
      },
    );
  }

  @override
  Future<void> reject(String expenseId, String reason) async {
    await _client.rpc<void>(
      'review_expense',
      params: {
        'p_expense_id': expenseId,
        'p_decision': 'rejected',
        'p_reason': reason,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> analytics(
    String householdId,
    DateTime from,
    DateTime until,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(
      'spending_analytics_window',
      params: {
        'p_household_id': householdId,
        'p_from': from.toIso8601String().substring(0, 10),
        'p_until': until.toIso8601String().substring(0, 10),
      },
    );
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> categories(String householdId) async {
    final rows = await _client
        .from('categories')
        .select('id, name')
        .eq('household_id', householdId)
        .isFilter('archived_at', null)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> budgets(String householdId) async {
    final month = DateTime.now();
    final rows = await _client
        .from('budgets')
        .select('id, amount_minor, month_start, categories(name)')
        .eq('household_id', householdId)
        .eq(
          'month_start',
          DateTime(month.year, month.month).toIso8601String().substring(0, 10),
        )
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> obligations(String householdId) async {
    final rows = await _client
        .from('obligations')
        .select('id, title, expected_amount_minor, frequency, active')
        .eq('household_id', householdId)
        .order('title');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<void> setBudget({
    required String householdId,
    required String categoryId,
    required DateTime month,
    required int amountMinor,
  }) async {
    await _client.rpc<void>('set_monthly_budget', params: {
      'p_household_id': householdId,
      'p_category_id': categoryId,
      'p_month_start':
          DateTime(month.year, month.month).toIso8601String().substring(0, 10),
      'p_amount_minor': amountMinor,
    });
  }

  @override
  Future<void> createObligation({
    required String householdId,
    required String title,
    required int expectedAmountMinor,
    required String categoryId,
    required String frequency,
    required DateTime startsOn,
  }) async {
    await _client.rpc<void>('create_obligation', params: {
      'p_household_id': householdId,
      'p_title': title,
      'p_expected_amount_minor': expectedAmountMinor,
      'p_category_id': categoryId,
      'p_frequency': frequency,
      'p_starts_on': startsOn.toIso8601String().substring(0, 10),
      'p_due_time': '09:00:00',
    });
  }
}
