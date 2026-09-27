import 'package:flutter/material.dart';
import 'package:home_management/src/features/household/domain/household.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({required this.household, super.key});

  final Household household;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
        children: [
          Text(
            'Hello, ${household.name}!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Here is what needs attention today.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          const _TodayCard(
            icon: Icons.task_alt,
            title: 'Chores',
            message: 'Open the Chores tab to see what is due today.',
          ),
          const SizedBox(height: 12),
          const _TodayCard(
            icon: Icons.event_available,
            title: 'Family calendar',
            message: 'Shared plans and deadlines stay together.',
          ),
          if (household.role.canReadLedger) ...[
            const SizedBox(height: 12),
            const _TodayCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Household spending',
              message: 'Review this month and any pending submissions.',
            ),
          ],
        ],
      );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(radius: 26, child: Icon(icon)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(message),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
