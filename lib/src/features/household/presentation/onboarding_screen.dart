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
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _timeZone.dispose();
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
