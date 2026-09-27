import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:home_management/src/core/domain/roles.dart';
import 'package:home_management/src/features/chores/data/chore_repository.dart';
import 'package:home_management/src/features/spending/data/spending_repository.dart';
import 'package:home_management/src/features/spending/domain/expense.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class OfflineCommandQueue {
  OfflineCommandQueue(this._spending, this._chores);

  static const _storageKey = 'offline_command_outbox_v1';
  final SpendingRepository _spending;
  final ChoreRepository _chores;

  Future<bool> get isOffline async {
    final results = await Connectivity().checkConnectivity();
    return results.every((result) => result == ConnectivityResult.none);
  }

  Future<void> enqueuePurchase(
    NewPurchase purchase,
    HouseholdRole role, {
    List<int>? receiptBytes,
  }) async {
    await _append({
      'type': 'purchase',
      'role': role.name,
      'payload': {
        'clientMutationId': purchase.clientMutationId,
        'householdId': purchase.householdId,
        'summary': purchase.summary,
        'totalMinor': purchase.totalMinor,
        'currencyCode': purchase.currencyCode,
        'incurredAt': purchase.incurredAt.toUtc().toIso8601String(),
        'payerUserId': purchase.payerUserId,
        'categoryId': purchase.categoryId,
        'paymentSourceId': purchase.paymentSourceId,
        'note': purchase.note,
        'receiptBase64':
            receiptBytes == null ? null : base64Encode(receiptBytes),
        'items': purchase.items
            .map(
              (item) => {
                'name': item.name,
                'amountMinor': item.amountMinor,
                'categoryId': item.categoryId,
              },
            )
            .toList(),
      },
    });
  }

  Future<void> enqueueChoreCompletion(String occurrenceId) => _append({
        'type': 'complete_chore',
        'payload': {'occurrenceId': occurrenceId},
      });

  Future<void> _append(Map<String, dynamic> command) async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_storageKey) ?? [];
    current.add(jsonEncode(command));
    await preferences.setStringList(_storageKey, current);
  }

  Future<int> synchronize() async {
    if (await isOffline) return 0;
    final preferences = await SharedPreferences.getInstance();
    final pending = [...?preferences.getStringList(_storageKey)];
    final remaining = <String>[];
    var completed = 0;
    for (final encoded in pending) {
      try {
        final command = jsonDecode(encoded) as Map<String, dynamic>;
        final payload = command['payload'] as Map<String, dynamic>;
        if (command['type'] == 'complete_chore') {
          await _chores.complete(payload['occurrenceId'] as String);
        } else if (command['type'] == 'purchase') {
          final items = (payload['items'] as List).cast<Map<String, dynamic>>();
          final expenseId = await _spending.createPurchase(
            NewPurchase(
              clientMutationId: payload['clientMutationId'] as String,
              householdId: payload['householdId'] as String,
              summary: payload['summary'] as String,
              totalMinor: payload['totalMinor'] as int,
              currencyCode: payload['currencyCode'] as String,
              incurredAt: DateTime.parse(payload['incurredAt'] as String),
              payerUserId: payload['payerUserId'] as String,
              categoryId: payload['categoryId'] as String?,
              paymentSourceId: payload['paymentSourceId'] as String?,
              note: payload['note'] as String?,
              items: items
                  .map(
                    (item) => PurchaseItem(
                      name: item['name'] as String,
                      amountMinor: item['amountMinor'] as int,
                      categoryId: item['categoryId'] as String?,
                    ),
                  )
                  .toList(),
            ),
            HouseholdRole.values.byName(command['role'] as String),
          );
          final receiptBase64 = payload['receiptBase64'] as String?;
          if (receiptBase64 != null) {
            await _spending.attachReceipt(
              expenseId,
              payload['householdId'] as String,
              base64Decode(receiptBase64),
            );
          }
        }
        completed += 1;
      } catch (_) {
        remaining.add(encoded);
      }
    }
    await preferences.setStringList(_storageKey, remaining);
    return completed;
  }
}
