import 'package:home_management/src/core/domain/money.dart';
import 'package:home_management/src/core/domain/roles.dart';

final class PurchaseItem {
  const PurchaseItem({
    required this.name,
    required this.amountMinor,
    this.categoryId,
  });

  final String name;
  final int amountMinor;
  final String? categoryId;
}

final class Expense {
  const Expense({
    required this.id,
    required this.householdId,
    required this.summary,
    required this.total,
    required this.incurredAt,
    required this.payerUserId,
    required this.status,
    required this.kind,
    required this.items,
    this.categoryId,
    this.paymentSourceId,
  });

  final String id;
  final String householdId;
  final String summary;
  final Money total;
  final DateTime incurredAt;
  final String payerUserId;
  final ExpenseStatus status;
  final ExpenseKind kind;
  final List<PurchaseItem> items;
  final String? categoryId;
  final String? paymentSourceId;
}

final class NewPurchase {
  const NewPurchase({
    required this.clientMutationId,
    required this.householdId,
    required this.summary,
    required this.totalMinor,
    required this.currencyCode,
    required this.incurredAt,
    required this.payerUserId,
    required this.items,
    this.categoryId,
    this.paymentSourceId,
    this.note,
  });

  final String clientMutationId;
  final String householdId;
  final String summary;
  final int totalMinor;
  final String currencyCode;
  final DateTime incurredAt;
  final String payerUserId;
  final List<PurchaseItem> items;
  final String? categoryId;
  final String? paymentSourceId;
  final String? note;

  void validate() {
    if (summary.trim().isEmpty) {
      throw ArgumentError('An item name is required.');
    }
    if (totalMinor <= 0) {
      throw ArgumentError('Amount must be positive.');
    }
    if (items.isEmpty) {
      throw ArgumentError('At least one purchase item is required.');
    }
    final itemTotal = items.fold<int>(0, (sum, item) => sum + item.amountMinor);
    if (itemTotal != totalMinor) {
      throw ArgumentError('Purchase item amounts must equal the total.');
    }
  }
}
