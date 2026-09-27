import 'package:flutter_test/flutter_test.dart';
import 'package:home_management/src/core/domain/roles.dart';
import 'package:home_management/src/core/offline/offline_command_queue.dart';
import 'package:home_management/src/core/offline/outbox_store.dart';
import 'package:home_management/src/features/spending/data/spending_repository.dart';
import 'package:home_management/src/features/spending/domain/expense.dart';
import 'package:home_management/src/features/chores/data/chore_repository.dart';
import 'package:mocktail/mocktail.dart';

class _Spending extends Mock implements SpendingRepository {}

class _Chores extends Mock implements ChoreRepository {}

class _MemoryStore implements OutboxStore {
  final commands = <String, Map<String, dynamic>>{};
  @override
  Future<void> insert(Map<String, dynamic> command) async {
    commands[command['id'] as String] = command;
  }

  @override
  Future<void> update(Map<String, dynamic> command) async {
    commands[command['id'] as String] = command;
  }

  @override
  Future<void> remove(String id) async {
    commands.remove(id);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String scope) async =>
      commands.values.where((c) => c['scope'] == scope).toList();
  @override
  Future<List<Map<String, dynamic>>> claim(String scope, DateTime now) async {
    final result = commands.values
        .where((c) => isReady(c, scope, now))
        .map((c) => lease(c, now))
        .toList();
    for (final command in result) {
      await update(command);
    }
    return result;
  }
}

void main() {
  final purchase = NewPurchase(
      clientMutationId: 'mutation',
      householdId: 'home',
      summary: 'Groceries',
      totalMinor: 100,
      currencyCode: 'BDT',
      incurredAt: DateTime(2026),
      payerUserId: 'owner',
      items: const [PurchaseItem(name: 'Groceries', amountMinor: 100)]);
  setUpAll(() {
    registerFallbackValue(purchase);
    registerFallbackValue(HouseholdRole.owner);
  });

  test('switching accounts never replays another account offline actions',
      () async {
    final spending = _Spending();
    final store = _MemoryStore();
    var userId = 'owner';
    final queue = OfflineCommandQueue(spending, _Chores(),
        currentUserId: () => userId,
        currentHouseholdId: () async => 'home',
        store: Future.value(store),
        offlineCheck: () async => false);
    await queue.enqueuePurchase(purchase, HouseholdRole.owner);
    userId = 'member';
    expect(await queue.synchronize(), 0);
    expect(await queue.pending('home'), isEmpty);
    expect(store.commands.length, 1);
    verifyNever(() => spending.createPurchase(any(), any()));
  });

  test(
      'failed receipt retries its attachment without creating a second purchase',
      () async {
    final spending = _Spending();
    final store = _MemoryStore();
    final queue = OfflineCommandQueue(spending, _Chores(),
        currentUserId: () => 'owner',
        currentHouseholdId: () async => 'home',
        store: Future.value(store),
        offlineCheck: () async => false);
    when(() => spending.createPurchase(any(), any()))
        .thenAnswer((_) async => 'expense');
    when(() => spending.attachReceipt('expense', 'home', any()))
        .thenThrow(Exception('Network interrupted'));
    await queue.enqueuePurchase(purchase, HouseholdRole.owner,
        receiptBytes: [1, 2, 3]);
    expect(await queue.synchronize(), 0);
    final command = store.commands.values.single;
    expect(command['expenseId'], 'expense');
    command['retryAt'] = DateTime(2020).toIso8601String();
    when(() => spending.attachReceipt('expense', 'home', any()))
        .thenAnswer((_) async {});
    expect(await queue.synchronize(), 1);
    expect(store.commands, isEmpty);
    verify(() => spending.createPurchase(any(), any())).called(1);
    verify(() => spending.attachReceipt('expense', 'home', [1, 2, 3]))
        .called(2);
  });

  test('concurrent sync calls cannot process the same saved action twice',
      () async {
    final spending = _Spending();
    final store = _MemoryStore();
    final queue = OfflineCommandQueue(spending, _Chores(),
        currentUserId: () => 'owner',
        currentHouseholdId: () async => 'home',
        store: Future.value(store),
        offlineCheck: () async => false);
    when(() => spending.createPurchase(any(), any()))
        .thenAnswer((_) async => 'expense');
    await queue.enqueuePurchase(purchase, HouseholdRole.owner);
    await Future.wait([queue.synchronize(), queue.synchronize()]);
    verify(() => spending.createPurchase(any(), any())).called(1);
  });
}
