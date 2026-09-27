import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/domain/money.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:intl/intl.dart';

final dashboardProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, householdId) => ref.watch(supabaseProvider).rpc<Map<String, dynamic>>(
    'household_dashboard',
    params: {'p_household_id': householdId},
  ),
);

class TodayScreen extends ConsumerWidget {
  const TodayScreen({required this.household, super.key});
  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardProvider(household.id));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardProvider(household.id));
        await ref.read(dashboardProvider(household.id).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
        children: [
          Text('Hello, ${household.name}!',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          StreamBuilder<DateTime>(
            stream: Stream.periodic(
                const Duration(minutes: 1), (_) => DateTime.now()),
            initialData: DateTime.now(),
            builder: (context, value) => Text(
              DateFormat.yMMMMEEEEd().add_jm().format(value.data!),
            ),
          ),
          const SizedBox(height: 20),
          ...snapshot.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (_, __) =>
                [const Text('Could not refresh today. Pull down to retry.')],
            data: (data) => [
              _TodayCard(
                  icon: Icons.task_alt,
                  title: 'Chores today',
                  message:
                      '${data['chores_due']} due today · ${data['chores_overdue']} overdue'),
              _TodayCard(
                  icon: Icons.event_available,
                  title: 'Family calendar',
                  message: '${data['events_today']} events today'),
              if (household.role.canReadLedger) ...[
                _TodayCard(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Spent this month',
                    message: Money(data['spent_month_minor'] as int,
                            household.currencyCode)
                        .format()),
                _TodayCard(
                    icon: Icons.pending_actions,
                    title: 'Needs attention',
                    message:
                        '${data['pending_submissions']} submissions to review · ${data['payments_due']} payments due within a week'),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard(
      {required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card.filled(
            child: ListTile(
          contentPadding: const EdgeInsets.all(20),
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title),
          subtitle: Text(message),
        )),
      );
}
