import 'package:intl/intl.dart';

final class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currencyCode);

  final int minorUnits;
  final String currencyCode;

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
