import 'package:flutter_test/flutter_test.dart';
import 'package:home_management/src/core/domain/roles.dart';

void main() {
  test('member cannot read the shared ledger', () {
    expect(HouseholdRole.member.canReadLedger, isFalse);
    expect(HouseholdRole.member.canOperateHousehold, isFalse);
  });

  test('manager operates but does not govern the household', () {
    expect(HouseholdRole.manager.canOperateHousehold, isTrue);
    expect(HouseholdRole.manager.canGovernHousehold, isFalse);
  });

  test('owner can govern the household', () {
    expect(HouseholdRole.owner.canGovernHousehold, isTrue);
  });
}
