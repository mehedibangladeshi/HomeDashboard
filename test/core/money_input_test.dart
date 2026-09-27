import 'package:flutter_test/flutter_test.dart';
import 'package:home_management/src/core/domain/money.dart';

void main() {
  test('decimal input converts exactly without floating point rounding', () {
    expect(Money.parseMinor('123.45'), 12345);
    expect(Money.parseMinor('0.29'), 29);
    expect(Money.parseMinor('12.5'), 1250);
    expect(Money.parseMinor('12'), 1200);
  });
  test('invalid and sub-cent input is rejected instead of silently rounded',
      () {
    for (final input in ['0', '-1', 'NaN', 'Infinity', '1.234', '']) {
      expect(() => Money.parseMinor(input), throwsFormatException);
    }
  });
}
