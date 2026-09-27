import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/domain/roles.dart';
import 'package:home_management/src/core/files/export_download.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:home_management/src/features/spending/presentation/finance_planning_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({required this.household, super.key});

  final Household household;

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    var role = HouseholdRole.member;
    final result = await showDialog<(String, HouseholdRole)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Invite family member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<HouseholdRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: HouseholdRole.values
                    .where(
                      (value) =>
                          household.role == HouseholdRole.owner ||
                          value == HouseholdRole.member,
                    )
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => role = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (email.text.trim().contains('@')) {
                  Navigator.pop(context, (email.text.trim(), role));
                }
              },
              child: const Text('Send invitation'),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    if (result == null) return;
    final response = await ref.read(supabaseProvider).functions.invoke(
      'invite-member',
      body: {
        'householdId': household.id,
        'email': result.$1,
        'role': result.$2.name,
      },
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.status == 200
                ? 'Invitation sent.'
                : 'Invitation failed: ${response.data}',
          ),
        ),
      );
    }
  }

  Future<void> _connectCalendar(BuildContext context, WidgetRef ref) async {
    final response = await ref.read(supabaseProvider).functions.invoke(
      'google-calendar-connect',
      body: {'householdId': household.id},
    );
    final data = response.data as Map<String, dynamic>?;
    final value = data?['authorizationUrl'] as String?;
    if (value == null ||
        !await launchUrl(Uri.parse(value),
            mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google authorization.')),
        );
      }
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final response = await ref.read(supabaseProvider).functions.invoke(
      'export-household',
      body: {'householdId': household.id},
    );
    final data = response.data;
    if (data is! Uint8List) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $data')),
        );
      }
      return;
    }
    final name =
        'home-management-${DateTime.now().toIso8601String().substring(0, 10)}.zip';
    final location = await downloadExportBytes(data, name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export saved to $location')),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this household?'),
        content: const Text(
          'Access will stop immediately. An Owner can restore it for 30 days before permanent deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Schedule deletion'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(supabaseProvider).rpc<void>(
      'mark_household_for_deletion',
      params: {'p_household_id': household.id},
    );
    ref.invalidate(currentHouseholdProvider);
  }

  Future<void> _quietHours(BuildContext context, WidgetRef ref) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 22, minute: 0),
      helpText: 'Quiet hours start',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
      helpText: 'Quiet hours end',
    );
    if (end == null) return;
    String encode(TimeOfDay value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00';
    final client = ref.read(supabaseProvider);
    await client.from('profiles').update({
      'quiet_hours_start': encode(start),
      'quiet_hours_end': encode(end),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', client.auth.currentUser!.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quiet hours updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card.filled(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
              title: Text(household.name),
              subtitle: Text(
                '${household.role.name} · ${household.currencyCode} · ${household.timeZone}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (household.role.canOperateHousehold) ...[
            Card.filled(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.account_balance_wallet_outlined),
                ),
                title: const Text('Budgets and recurring payments'),
                subtitle: const Text('Plan category limits and due dates'),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FinancePlanningScreen(household: household),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card.filled(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_add_alt)),
              title: const Text('Invite a family member'),
              subtitle: const Text('Invitations expire after seven days'),
              onTap: household.role.canOperateHousehold
                  ? () => _invite(context, ref)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Card.filled(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.group_outlined)),
              title: const Text('Household members'),
              subtitle: Text(
                household.role.canGovernHousehold
                    ? 'Manage roles and access'
                    : 'View members and manage basic access',
              ),
              onTap: household.role.canOperateHousehold
                  ? () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _MemberManagementScreen(
                            household: household,
                          ),
                        ),
                      )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Card.filled(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.notifications_outlined),
              ),
              title: const Text('Notifications and quiet hours'),
              subtitle: const Text('Balanced household defaults'),
              onTap: () => _quietHours(context, ref),
            ),
          ),
          const SizedBox(height: 12),
          Card.filled(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.calendar_month_outlined),
              ),
              title: const Text('Connect Google Calendar'),
              subtitle: const Text('Dedicated two-way household calendar'),
              onTap: household.role.canGovernHousehold
                  ? () => _connectCalendar(context, ref)
                  : null,
            ),
          ),
          if (household.role.canGovernHousehold) ...[
            const SizedBox(height: 12),
            Card.filled(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.download)),
                title: const Text('Export household data'),
                subtitle:
                    const Text('CSV archive with receipts and audit history'),
                onTap: () => _export(context, ref),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete household'),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      );
}

class _MemberManagementScreen extends ConsumerStatefulWidget {
  const _MemberManagementScreen({required this.household});

  final Household household;

  @override
  ConsumerState<_MemberManagementScreen> createState() =>
      _MemberManagementScreenState();
}

class _MemberManagementScreenState
    extends ConsumerState<_MemberManagementScreen> {
  late Future<List<HouseholdMember>> _members;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _members =
        ref.read(householdRepositoryProvider).members(widget.household.id);
  }

  Future<void> _changeRole(
    HouseholdMember member,
    HouseholdRole role,
  ) async {
    try {
      await ref.read(householdRepositoryProvider).updateMemberRole(
            householdId: widget.household.id,
            userId: member.userId,
            role: role,
          );
      setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change role: $error')),
        );
      }
    }
  }

  Future<void> _remove(HouseholdMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: const Text(
          'They will lose access to this household immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(householdRepositoryProvider).removeMember(
            householdId: widget.household.id,
            userId: member.userId,
          );
      setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove member: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.read(supabaseProvider).auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Household members')),
      body: FutureBuilder<List<HouseholdMember>>(
        future: _members,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Could not load members: ${snapshot.error}'));
          }
          final members = snapshot.data ?? const <HouseholdMember>[];
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = members[index];
              final isSelf = member.userId == currentUserId;
              final canChangeRole =
                  widget.household.role.canGovernHousehold && !isSelf;
              final canRemove = !isSelf &&
                  (widget.household.role.canGovernHousehold ||
                      member.role == HouseholdRole.member);
              return Card.filled(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      member.displayName.trim().isEmpty
                          ? '?'
                          : member.displayName.trim()[0].toUpperCase(),
                    ),
                  ),
                  title: Text(member.displayName),
                  subtitle: Text(
                    '${member.role.name}${isSelf ? ' · you' : ''}',
                  ),
                  trailing: canChangeRole || canRemove
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'remove') {
                              _remove(member);
                            } else {
                              _changeRole(
                                member,
                                HouseholdRole.values.byName(value),
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            if (canChangeRole)
                              ...HouseholdRole.values.map(
                                (role) => PopupMenuItem(
                                  value: role.name,
                                  enabled: role != member.role,
                                  child: Text('Make ${role.name}'),
                                ),
                              ),
                            if (canRemove)
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove access'),
                              ),
                          ],
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
