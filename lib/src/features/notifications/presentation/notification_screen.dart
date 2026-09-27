import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:intl/intl.dart';

final notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseProvider);
  return await client
      .from('notifications')
      .select('id,title,body,status,scheduled_for,read_at')
      .eq('user_id', client.auth.currentUser!.id)
      .lte('scheduled_for', DateTime.now().toUtc().toIso8601String())
      .order('scheduled_for', ascending: false)
      .limit(100);
});

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ref.watch(notificationsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(notificationsProvider),
                      child: const Text('Retry notifications'))),
              data: (rows) => rows.isEmpty
                  ? const Center(child: Text('No notifications yet.'))
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(notificationsProvider);
                        await ref.read(notificationsProvider.future);
                      },
                      child: ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            return ListTile(
                              leading: Icon(row['read_at'] == null
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_none),
                              title: Text(row['title'] as String),
                              subtitle: Text(
                                  '${row['body']}\n${DateFormat.MMMd().add_jm().format(DateTime.parse(row['scheduled_for'] as String).toLocal())}'),
                              isThreeLine: true,
                              onTap: () async {
                                await ref
                                    .read(supabaseProvider)
                                    .from('notifications')
                                    .update({
                                  'read_at':
                                      DateTime.now().toUtc().toIso8601String(),
                                }).eq('id', row['id'] as String);
                                ref.invalidate(notificationsProvider);
                              },
                            );
                          })),
            ),
      );
}
