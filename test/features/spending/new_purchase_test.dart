import 'package:flutter_test/flutter_test.dart';
import 'package:home_management/src/features/spending/domain/expense.dart';

void main() {
  NewPurchase purchase({
    required int total,
    required List<PurchaseItem> items,
  }) =>
      NewPurchase(
        clientMutationId: 'mutation-1',
        householdId: 'household-1',
        summary: 'Weekly groceries',
        totalMinor: total,
        currencyCode: 'BDT',
        incurredAt: DateTime.utc(2026, 9, 27),
        payerUserId: 'user-1',
        items: items,
      );

  test('accepts a summary item matching the purchase total', () {
    expect(
      () => purchase(
        total: 12500,
        items: const [
          PurchaseItem(name: 'Weekly groceries', amountMinor: 12500),
        ],
      ).validate(),
      returnsNormally,
    );
  });

  test('accepts detailed items when they reconcile exactly', () {
    expect(
      () => purchase(
        total: 300,
        items: const [
          PurchaseItem(name: 'Rice', amountMinor: 200),
          PurchaseItem(name: 'Milk', amountMinor: 100),
        ],
      ).validate(),
      returnsNormally,
    );
  });

  test('rejects item totals that do not reconcile', () {
    expect(
      () => purchase(
        total: 300,
        items: const [PurchaseItem(name: 'Rice', amountMinor: 200)],
      ).validate(),
      throwsArgumentError,
    );
  });
}
