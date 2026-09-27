import 'package:home_management/src/core/domain/roles.dart';

final class Household {
  const Household({
    required this.id,
    required this.name,
    required this.currencyCode,
    required this.timeZone,
    required this.role,
  });

  final String id;
  final String name;
  final String currencyCode;
  final String timeZone;
  final HouseholdRole role;

  factory Household.fromJson(Map<String, dynamic> json) => Household(
        id: json['id'] as String,
        name: json['name'] as String,
        currencyCode: json['currency_code'] as String,
        timeZone: json['time_zone'] as String,
        role: HouseholdRole.values.byName(json['role'] as String),
      );
}

final class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final HouseholdRole role;
}
