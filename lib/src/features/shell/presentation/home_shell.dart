import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/features/calendar/presentation/calendar_screen.dart';
import 'package:home_management/src/features/chores/presentation/chores_screen.dart';
import 'package:home_management/src/features/dashboard/presentation/today_screen.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:home_management/src/features/settings/presentation/settings_screen.dart';
import 'package:home_management/src/features/spending/presentation/spending_screen.dart';
import 'package:home_management/src/core/offline/pending_sync_bar.dart';
import 'package:home_management/src/features/notifications/presentation/notification_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.household, super.key});

  final Household household;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      TodayScreen(household: widget.household),
      SpendingScreen(household: widget.household),
      ChoresScreen(household: widget.household),
      CalendarScreen(household: widget.household),
      SettingsScreen(household: widget.household),
    ];
    const titles = ['Today', 'Spending', 'Chores', 'Calendar', 'More'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_index]), actions: [
        IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push<void>(context,
                MaterialPageRoute(builder: (_) => const NotificationScreen()))),
      ]),
      body: Column(children: [
        PendingSyncBar(householdId: widget.household.id),
        Expanded(child: IndexedStack(index: _index, children: screens)),
      ]),
      floatingActionButton: switch (_index) {
        1 => FloatingActionButton.extended(
            onPressed: () =>
                showQuickPurchaseSheet(context, ref, widget.household),
            icon: const Icon(Icons.add),
            label: Text(
              widget.household.role.canReadLedger ? 'Purchase' : 'Submit',
            ),
          ),
        2 => FloatingActionButton.extended(
            onPressed: () =>
                showCreateChoreSheet(context, ref, widget.household),
            icon: const Icon(Icons.add_task),
            label: const Text('Chore'),
          ),
        3 => FloatingActionButton.extended(
            onPressed: () =>
                showCreateEventSheet(context, ref, widget.household),
            icon: const Icon(Icons.event),
            label: const Text('Event'),
          ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            label: 'Spending',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            label: 'Chores',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendar',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
