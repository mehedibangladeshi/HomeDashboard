import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/domain/money.dart';
import 'package:home_management/src/features/household/domain/household.dart';

class FinancePlanningScreen extends ConsumerStatefulWidget {
  const FinancePlanningScreen({required this.household, super.key});

  final Household household;

  @override
  ConsumerState<FinancePlanningScreen> createState() =>
      _FinancePlanningScreenState();
}

class _FinancePlanningScreenState extends ConsumerState<FinancePlanningScreen> {
  late Future<
      (
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      )> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repository = ref.read(spendingRepositoryProvider);
    _data = (
      repository.categories(widget.household.id),
      repository.budgets(widget.household.id),
      repository.obligations(widget.household.id),
    ).wait;
  }

  Future<void> _addBudget(List<Map<String, dynamic>> categories) async {
    final amount = TextEditingController();
    var categoryId = categories.first['id'] as String;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Monthly budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: categories
                    .map((category) => DropdownMenuItem(
                          value: category['id'] as String,
                          child: Text(category['name'] as String),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => categoryId = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Amount (${widget.household.currencyCode})'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text);
                if (value != null && value > 0) {
                  Navigator.pop(context, (categoryId, (value * 100).round()));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    if (result == null) return;
    await ref.read(spendingRepositoryProvider).setBudget(
          householdId: widget.household.id,
          categoryId: result.$1,
          month: DateTime.now(),
          amountMinor: result.$2,
        );
    setState(_reload);
  }

  Future<void> _addObligation(List<Map<String, dynamic>> categories) async {
    final title = TextEditingController();
    final amount = TextEditingController();
    var categoryId = categories.first['id'] as String;
    var frequency = 'monthly';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Recurring obligation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText:
                          'Expected amount (${widget.household.currencyCode})'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map((category) => DropdownMenuItem(
                            value: category['id'] as String,
                            child: Text(category['name'] as String),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => categoryId = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: frequency,
                  decoration: const InputDecoration(labelText: 'Repeats'),
                  items: const [
                    'once',
                    'daily',
                    'weekdays',
                    'weekly',
                    'monthly'
                  ]
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setState(() => frequency = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (accepted == true) {
      final value = double.tryParse(amount.text);
      if (title.text.trim().isNotEmpty && value != null && value > 0) {
        await ref.read(spendingRepositoryProvider).createObligation(
              householdId: widget.household.id,
              title: title.text.trim(),
              expectedAmountMinor: (value * 100).round(),
              categoryId: categoryId,
              frequency: frequency,
              startsOn: DateTime.now(),
            );
        setState(_reload);
      }
    }
    title.dispose();
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Budgets and recurring payments')),
        body: FutureBuilder(
          future: _data,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (categories, budgets, obligations) = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('This month’s budgets',
                        style: Theme.of(context).textTheme.titleLarge),
                    IconButton(
                        onPressed: () => _addBudget(categories),
                        icon: const Icon(Icons.add)),
                  ],
                ),
                if (budgets.isEmpty) const Text('No category budgets yet.'),
                ...budgets.map((budget) => Card.filled(
                      child: ListTile(
                        title: Text((budget['categories']
                            as Map<String, dynamic>)['name'] as String),
                        trailing: Text(Money(budget['amount_minor'] as int,
                                widget.household.currencyCode)
                            .format()),
                      ),
                    )),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recurring payments',
                        style: Theme.of(context).textTheme.titleLarge),
                    IconButton(
                        onPressed: () => _addObligation(categories),
                        icon: const Icon(Icons.add)),
                  ],
                ),
                if (obligations.isEmpty)
                  const Text('No recurring obligations yet.'),
                ...obligations.map((obligation) => Card.filled(
                      child: ListTile(
                        leading:
                            const CircleAvatar(child: Icon(Icons.event_repeat)),
                        title: Text(obligation['title'] as String),
                        subtitle: Text(obligation['frequency'] as String),
                        trailing: obligation['expected_amount_minor'] == null
                            ? null
                            : Text(Money(
                                    obligation['expected_amount_minor'] as int,
                                    widget.household.currencyCode)
                                .format()),
                      ),
                    )),
              ],
            );
          },
        ),
      );
}
