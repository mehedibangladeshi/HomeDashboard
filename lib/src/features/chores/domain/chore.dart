import 'package:home_management/src/core/domain/roles.dart';

final class Chore {
  const Chore({
    required this.id,
    required this.householdId,
    required this.title,
    required this.assigneeUserId,
    required this.frequency,
    required this.nextDueAt,
  });

  final String id;
  final String householdId;
  final String title;
  final String assigneeUserId;
  final ChoreFrequency frequency;
  final DateTime nextDueAt;
}

final class ChoreOccurrence {
  const ChoreOccurrence({
    required this.id,
    required this.choreId,
    required this.title,
    required this.assigneeUserId,
    required this.dueAt,
    this.completedAt,
  });

  final String id;
  final String choreId;
  final String title;
  final String assigneeUserId;
  final DateTime dueAt;
  final DateTime? completedAt;

  bool get isComplete => completedAt != null;
  bool get isOverdue => !isComplete && dueAt.isBefore(DateTime.now());
}
