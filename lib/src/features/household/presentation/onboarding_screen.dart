import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController(text: 'Our Home');
  final _currency = TextEditingController(text: 'BDT');
  final _timeZone = TextEditingController(text: 'Asia/Dhaka');
  final _invitation = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _timeZone.dispose();
    _invitation.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(householdRepositoryProvider).create(
            name: _name.text.trim(),
            currencyCode: _currency.text.trim().toUpperCase(),
            timeZone: _timeZone.text.trim(),
          );
      ref.invalidate(currentHouseholdProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not create the household. Check its details or restore your existing home.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create your household')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                      controller: _invitation,
                      decoration: const InputDecoration(
                          labelText: 'Invitation code (if joining a home)')),
                  TextButton(
                      onPressed: () async {
                        if (_invitation.text.trim().isEmpty) return;
                        try {
                          await ref.read(supabaseProvider).rpc<String>(
                              'accept_household_invitation',
                              params: {'p_token': _invitation.text.trim()});
                          ref.invalidate(currentHouseholdProvider);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'This invitation is invalid, expired or for a different email.')));
                          }
                        }
                      },
                      child: const Text('Join invited household')),
                  FutureBuilder<List<dynamic>>(
                    future: ref
                        .read(supabaseProvider)
                        .rpc<List<dynamic>>('recoverable_households'),
                    builder: (context, snapshot) => Column(children: [
                      for (final row in snapshot.data ?? const <dynamic>[])
                        Card.filled(
                            child: ListTile(
                          title: Text('Restore ${row['name']}'),
                          subtitle: Text(
                              'Recovery available until ${row['purge_after']}'),
                          trailing: TextButton(
                              child: const Text('Restore'),
                              onPressed: () async {
                                await ref.read(supabaseProvider).rpc<void>(
                                    'restore_household',
                                    params: {'p_household_id': row['id']});
                                ref.invalidate(currentHouseholdProvider);
                              }),
                        )),
                    ]),
                  ),
                  TextField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Household name'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _currency,
                    maxLength: 3,
                    textCapitalization: TextCapitalization.characters,
                    decoration:
                        const InputDecoration(labelText: 'Currency code'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _timeZone,
                    decoration: const InputDecoration(labelText: 'Time zone'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _create,
                    child: Text(_busy ? 'Creating…' : 'Create household'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
