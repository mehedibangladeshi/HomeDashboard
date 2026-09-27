import 'package:intl/intl.dart';

final class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currencyCode);

  final int minorUnits;
  final String currencyCode;

  static int parseMinor(String input) {
    if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(input.trim())) {
      throw const FormatException(
          'Enter an amount with at most two decimal places.');
    }
    final parts = input.trim().split('.');
    final minor = int.parse(parts.first) * 100 +
        (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
    if (minor <= 0) throw const FormatException('Amount must be positive.');
    return minor;
  }

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currencyCode);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currencyCode);
  }

  void _requireSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw ArgumentError('Cannot combine different currencies.');
    }
  }

  String format({String? locale}) => NumberFormat.simpleCurrency(
        name: currencyCode,
        locale: locale,
      ).format(minorUnits / 100);

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);
}
