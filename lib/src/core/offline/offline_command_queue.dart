import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:home_management/src/core/domain/roles.dart';
import 'package:home_management/src/features/chores/data/chore_repository.dart';
import 'package:home_management/src/features/spending/data/spending_repository.dart';
import 'package:home_management/src/features/spending/domain/expense.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'outbox_store.dart';

final class OfflineCommandQueue {
  OfflineCommandQueue(
    this._spending,
    this._chores, {
    required this.currentUserId,
    required this.currentHouseholdId,
    Future<OutboxStore>? store,
    Future<bool> Function()? offlineCheck,
  })  : _store = store ?? openOutboxStore(),
        _offlineCheck = offlineCheck;

  final SpendingRepository _spending;
  final ChoreRepository _chores;
  final String? Function() currentUserId;
  final Future<String?> Function() currentHouseholdId;
  final Future<OutboxStore> _store;
  final Future<bool> Function()? _offlineCheck;
  Future<int>? _running;

  Future<bool> get isOffline async {
    if (_offlineCheck != null) return _offlineCheck();
    final results = await Connectivity().checkConnectivity();
    return results.every((result) => result == ConnectivityResult.none);
  }

  String scope(String householdId) {
    final userId = currentUserId();
    if (userId == null) throw StateError('Sign in before saving offline work.');
    return '$userId:$householdId';
  }

  Future<void> enqueuePurchase(
    NewPurchase purchase,
    HouseholdRole role, {
    List<int>? receiptBytes,
  }) async {
    purchase.validate();
    await _append(purchase.householdId, {
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
            .map((item) => {
                  'name': item.name,
                  'amountMinor': item.amountMinor,
                  'categoryId': item.categoryId,
                })
            .toList(),
      },
    });
  }

  Future<void> enqueueChoreCompletion(
          String occurrenceId, String householdId) =>
      _append(householdId, {
        'type': 'complete_chore',
        'payload': {'occurrenceId': occurrenceId},
      });

  Future<void> _append(String householdId, Map<String, dynamic> command) async {
    final commandScope = scope(householdId);
    await (await _store).insert({
      ...command,
      'id': const Uuid().v4(),
      'scope': commandScope,
      'state': 'pending',
      'attempts': 0,
      'leaseUntil': null,
      'retryAt': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> pending(String householdId) async =>
      (await _store).list(scope(householdId));

  Future<void> retryFailed(String householdId) async {
    final store = await _store;
    for (final command in await store.list(scope(householdId))) {
      if (command['state'] != 'failed') continue;
      await store.update({
        ...command,
        'state': 'pending',
        'lastError': null,
        'retryAt': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toUtc()
            .toIso8601String()
      });
    }
  }

  Future<int> synchronize() {
    if (_running != null) return _running!;
    final future = _synchronize();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<int> _synchronize() async {
    final userId = currentUserId();
    if (userId == null || await isOffline) return 0;
    final householdId = await currentHouseholdId();
    if (householdId == null || currentUserId() != userId) return 0;
    final commandScope = '$userId:$householdId';
    final store = await _store;
    final pending = await store.claim(commandScope, DateTime.now().toUtc());
    var completed = 0;
    for (final command in pending) {
      if (currentUserId() != userId) break;
      try {
        final payload = Map<String, dynamic>.from(command['payload'] as Map);
        if (command['type'] == 'complete_chore') {
          await _chores.complete(payload['occurrenceId'] as String);
        } else if (command['type'] == 'purchase') {
          String? expenseId = command['expenseId'] as String?;
          if (expenseId == null) {
            expenseId = await _spending.createPurchase(
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
                items: (payload['items'] as List).map((row) {
                  final item = Map<String, dynamic>.from(row as Map);
                  return PurchaseItem(
                      name: item['name'] as String,
                      amountMinor: item['amountMinor'] as int,
                      categoryId: item['categoryId'] as String?);
                }).toList(),
              ),
              HouseholdRole.values.byName(command['role'] as String),
            );
            command['expenseId'] = expenseId;
            await store.update(command);
          }
          if (currentUserId() != userId) break;
          final receiptBase64 = payload['receiptBase64'] as String?;
          if (receiptBase64 != null) {
            await _spending.attachReceipt(
                expenseId, householdId, base64Decode(receiptBase64));
          }
        } else {
          throw StateError('Unknown offline command.');
        }
        await store.remove(command['id'] as String);
        completed++;
      } catch (error) {
        final attempts = (command['attempts'] as int) + 1;
        final permanent = error is PostgrestException &&
            ['42501', 'P0001', '23503', '23514'].contains(error.code);
        await store.update({
          ...command,
          'state': permanent ? 'failed' : 'pending',
          'attempts': attempts,
          'leaseUntil': null,
          'lastError': permanent
              ? 'This action is no longer allowed. Review it before retrying.'
              : 'Waiting to reconnect.',
          'retryAt': DateTime.now()
              .add(
                  Duration(seconds: min(300, pow(2, min(attempts, 8)).toInt())))
              .toUtc()
              .toIso8601String(),
        });
      }
    }
    return completed;
  }
}
