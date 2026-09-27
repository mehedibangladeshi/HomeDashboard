import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/features/chores/domain/chore.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:home_management/src/core/domain/roles.dart';

final choreOccurrencesProvider =
    FutureProvider.family<List<ChoreOccurrence>, String>(
  (ref, householdId) =>
      ref.watch(choreRepositoryProvider).upcoming(householdId),
);

class ChoresScreen extends ConsumerWidget {
  const ChoresScreen({required this.household, super.key});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(choreOccurrencesProvider(household.id));
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(choreOccurrencesProvider(household.id).future),
      child: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          children: [
            Padding(padding: const EdgeInsets.all(24), child: Text('$error')),
          ],
        ),
        data: (items) => items.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.celebration_outlined, size: 72),
                  SizedBox(height: 16),
                  Text(
                    'Nothing on the chore list!',
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card.filled(
                    child: CheckboxListTile(
                      value: item.isComplete,
                      title: Text(item.title),
                      subtitle: Text(
                        '${item.isOverdue ? 'Overdue · ' : ''}${DateFormat.MMMEd().add_jm().format(item.dueAt)}',
                      ),
                      secondary: CircleAvatar(
                        child: Icon(
                          item.isComplete
                              ? Icons.celebration
                              : Icons.cleaning_services,
                        ),
                      ),
                      onChanged: item.isComplete
                          ? null
                          : (_) async {
                              final queue = ref.read(
                                offlineCommandQueueProvider,
                              );
                              if (await queue.isOffline) {
                                await queue.enqueueChoreCompletion(item.id);
                              } else {
                                await ref
                                    .read(choreRepositoryProvider)
                                    .complete(item.id);
                              }
                              ref.invalidate(
                                choreOccurrencesProvider(household.id),
                              );
                            },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

Future<void> showCreateChoreSheet(
  BuildContext context,
  WidgetRef ref,
  Household household,
) async {
  final title = TextEditingController();
  final members =
      await ref.read(householdRepositoryProvider).members(household.id);
  if (!context.mounted) return;
  var assignee = household.role.canOperateHousehold
      ? members.first.userId
      : Supabase.instance.client.auth.currentUser!.id;
  var frequency = ChoreFrequency.once;
  var due = DateTime.now().add(const Duration(hours: 2));
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
            Text('Add a chore', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'What needs doing?'),
            ),
            const SizedBox(height: 12),
            if (household.role.canOperateHousehold)
              DropdownButtonFormField<String>(
                initialValue: assignee,
                decoration: const InputDecoration(
                  labelText: 'Responsible person',
                ),
                items: members
                    .map(
                      (member) => DropdownMenuItem(
                        value: member.userId,
                        child: Text(member.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => assignee = value!),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ChoreFrequency>(
              initialValue: frequency,
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: ChoreFrequency.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => frequency = value!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: due,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(due),
                );
                if (time != null) {
                  setState(
                    () => due = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat.MMMEd().add_jm().format(due)),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                await ref.read(choreRepositoryProvider).create(
                      householdId: household.id,
                      title: title.text.trim(),
                      assigneeUserId: assignee,
                      frequency: frequency,
                      startsAt: due,
                    );
                ref.invalidate(choreOccurrencesProvider(household.id));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Add chore'),
            ),
          ],
        ),
      ),
    ),
  );
  title.dispose();
}
