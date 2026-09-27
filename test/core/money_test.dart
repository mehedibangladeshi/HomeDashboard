import 'package:flutter_test/flutter_test.dart';
import 'package:home_management/src/core/domain/money.dart';

void main() {
  group('Money', () {
    test('adds minor units without floating point arithmetic', () {
      expect(
        const Money(1050, 'BDT') + const Money(250, 'BDT'),
        const Money(1300, 'BDT'),
      );
    });

    test('rejects operations across household currencies', () {
      expect(
        () => const Money(100, 'BDT') + const Money(100, 'USD'),
        throwsArgumentError,
      );
    });
  });
}
