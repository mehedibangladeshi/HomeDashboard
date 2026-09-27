import 'package:flutter/material.dart';
import 'package:home_management/src/core/presentation/managed_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:intl/intl.dart';

final householdEventsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, householdId) =>
      ref.watch(calendarRepositoryProvider).events(householdId),
);

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({required this.household, super.key});

  final Household household;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(householdEventsProvider(widget.household.id));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        CalendarDatePicker(
          initialDate: DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 3650)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          onDateChanged: (value) => setState(() => selected = value),
        ),
        const SizedBox(height: 12),
        Text(DateFormat.yMMMMd().format(selected),
            style: Theme.of(context).textTheme.titleLarge),
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
              : rows.where((row) {
                  final from =
                      DateTime.parse(row['starts_at'] as String).toLocal();
                  final until =
                      DateTime.parse(row['ends_at'] as String).toLocal();
                  final day =
                      DateTime(selected.year, selected.month, selected.day);
                  return from.isBefore(day.add(const Duration(days: 1))) &&
                      until.isAfter(day);
                }).map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card.filled(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.event)),
                        title: Text(row['title'] as String),
                        onTap: () async {
                          final result = await showDialog<
                                  (String, DateTime, DateTime, bool)>(
                              context: context,
                              builder: (_) => _EventEditDialog(row: row));
                          if (result == null) return;
                          try {
                            final rows = await ref
                                .read(supabaseProvider)
                                .from('household_events')
                                .update({
                                  'title': result.$1,
                                  'starts_at':
                                      result.$2.toUtc().toIso8601String(),
                                  'ends_at':
                                      result.$3.toUtc().toIso8601String(),
                                  'status':
                                      result.$4 ? 'cancelled' : 'scheduled',
                                  'updated_at':
                                      DateTime.now().toUtc().toIso8601String(),
                                })
                                .eq('id', row['id'] as String)
                                .eq('updated_at', row['updated_at'] as String)
                                .select('id');
                            if (rows.isEmpty) throw StateError('Event changed');
                            ref.invalidate(
                                householdEventsProvider(widget.household.id));
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Could not update the event. Reload if someone else changed it.')));
                            }
                          }
                        },
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
  await showManagedBottomSheet<void>(
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

class _EventEditDialog extends StatefulWidget {
  const _EventEditDialog({required this.row});
  final Map<String, dynamic> row;
  @override
  State<_EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends State<_EventEditDialog> {
  late final title = TextEditingController(text: widget.row['title'] as String);
  late DateTime starts =
      DateTime.parse(widget.row['starts_at'] as String).toLocal();
  late DateTime ends =
      DateTime.parse(widget.row['ends_at'] as String).toLocal();
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> _time(bool start) async {
    final current = start ? starts : ends;
    final date = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time != null && mounted) {
      setState(() {
        final value =
            DateTime(date.year, date.month, date.day, time.hour, time.minute);
        if (start) {
          starts = value;
          if (!ends.isAfter(starts)) {
            ends = starts.add(const Duration(hours: 1));
          }
        } else {
          ends = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit family event'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Event name')),
          TextButton(
              onPressed: () => _time(true),
              child:
                  Text('Starts: ${DateFormat.MMMd().add_jm().format(starts)}')),
          TextButton(
              onPressed: () => _time(false),
              child: Text('Ends: ${DateFormat.MMMd().add_jm().format(ends)}')),
          if (!ends.isAfter(starts)) const Text('End must be after start.'),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(
                  context, (title.text.trim(), starts, ends, true)),
              child: const Text('Cancel event')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          FilledButton(
              onPressed: title.text.trim().isEmpty || !ends.isAfter(starts)
                  ? null
                  : () => Navigator.pop(
                      context, (title.text.trim(), starts, ends, false)),
              child: const Text('Save')),
        ],
      );
}
