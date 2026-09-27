enum HouseholdRole {
  owner,
  manager,
  member;

  bool get canReadLedger => this != HouseholdRole.member;
  bool get canOperateHousehold => this != HouseholdRole.member;
  bool get canGovernHousehold => this == HouseholdRole.owner;
}

enum ExpenseStatus { pending, approved, rejected, voided }

enum ExpenseKind { purchase, obligationPayment, other }

enum ChoreFrequency { once, daily, weekdays, weekly, monthly }
