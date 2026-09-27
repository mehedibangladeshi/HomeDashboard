import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:intl/intl.dart';

final householdEventsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, householdId) =>
      ref.watch(calendarRepositoryProvider).events(householdId),
);

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({required this.household, super.key});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(householdEventsProvider(household.id));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        CalendarDatePicker(
          initialDate: DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 3650)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          onDateChanged: (_) {},
        ),
        const SizedBox(height: 12),
        Text('Upcoming', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...events.when(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (error, _) => [Text('Could not load events: $error')],
          data: (rows) => rows.isEmpty
              ? [
                  const Card.filled(
                    child: ListTile(title: Text('No upcoming family events')),
                  ),
                ]
              : rows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card.filled(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.event)),
                        title: Text(row['title'] as String),
                        subtitle: Text(
                          DateFormat.MMMEd().add_jm().format(
                                DateTime.parse(row['starts_at'] as String)
                                    .toLocal(),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        const Card.filled(
          child: ListTile(
            leading: CircleAvatar(child: Icon(Icons.sync)),
            title: Text('Google Calendar'),
            subtitle: Text(
              'An Owner can connect the dedicated calendar in Settings.',
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showCreateEventSheet(
  BuildContext context,
  WidgetRef ref,
  Household household,
) async {
  final title = TextEditingController();
  var startsAt = DateTime.now().add(const Duration(hours: 1));
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Family event', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Event name'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat.MMMEd().add_jm().format(startsAt)),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: startsAt,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(startsAt),
                );
                if (time != null) {
                  setState(
                    () => startsAt = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                await ref.read(calendarRepositoryProvider).createEvent(
                      householdId: household.id,
                      title: title.text.trim(),
                      startsAt: startsAt,
                      endsAt: startsAt.add(const Duration(hours: 1)),
                    );
                ref.invalidate(householdEventsProvider(household.id));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Add event'),
            ),
          ],
        ),
      ),
    ),
  );
  title.dispose();
}
