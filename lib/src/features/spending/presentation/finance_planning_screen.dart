import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/domain/money.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:uuid/uuid.dart';
import 'package:home_management/src/core/presentation/managed_routes.dart';
import 'package:home_management/src/features/spending/presentation/spending_screen.dart';
import 'package:home_management/src/features/dashboard/presentation/today_screen.dart';

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
      ref
          .read(supabaseProvider)
          .from('obligation_occurrences')
          .select('id,title_snapshot,due_at,obligations(expected_amount_minor)')
          .eq('household_id', widget.household.id)
          .eq('status', 'scheduled')
          .order('due_at')
          .limit(50),
    ).wait;
  }

  Future<void> _addBudget(List<Map<String, dynamic>> categories) async {
    final amount = TextEditingController();
    var categoryId = categories.first['id'] as String;
    final result = await showManagedDialog<(String, int)>(
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
                try {
                  Navigator.pop(
                      context, (categoryId, Money.parseMinor(amount.text)));
                } on FormatException {
                  /* Keep the form open for a valid amount. */
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
    var startsOn = DateTime.now();
    final accepted = await showManagedDialog<bool>(
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
                OutlinedButton(
                    onPressed: () async {
                      final value = await showDatePicker(
                          context: context,
                          initialDate: startsOn,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 3650)));
                      if (value != null) setState(() => startsOn = value);
                    },
                    child: Text(
                        'First due date: ${startsOn.toIso8601String().substring(0, 10)}')),
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
      int? value;
      try {
        value = Money.parseMinor(amount.text);
      } on FormatException {
        value = null;
      }
      if (title.text.trim().isNotEmpty && value != null) {
        await ref.read(spendingRepositoryProvider).createObligation(
              householdId: widget.household.id,
              title: title.text.trim(),
              expectedAmountMinor: value,
              categoryId: categoryId,
              frequency: frequency,
              startsOn: startsOn,
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
            if (snapshot.hasError) {
              return Center(
                  child: TextButton(
                      onPressed: () => setState(_reload),
                      child: const Text('Reload planning')));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (categories, budgets, obligations, dues) = snapshot.data!;
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
                const SizedBox(height: 24),
                Text('Upcoming payments',
                    style: Theme.of(context).textTheme.titleLarge),
                if (dues.isEmpty) const Text('No unpaid occurrences.'),
                ...dues.map((due) => Card.filled(
                        child: ListTile(
                      title: Text(due['title_snapshot'] as String),
                      subtitle: Text(DateTime.parse(due['due_at'] as String)
                          .toLocal()
                          .toString()),
                      trailing: TextButton(
                          onPressed: () => _pay(due),
                          child: const Text('Record payment')),
                    ))),
              ],
            );
          },
        ),
      );

  Future<void> _pay(Map<String, dynamic> due) async {
    final definition = due['obligations'] as Map<String, dynamic>?;
    final value = await showDialog<int>(
        context: context,
        builder: (_) => _PaymentDialog(
            expectedMinor: definition?['expected_amount_minor'] as int?));
    if (value == null) return;
    try {
      final client = ref.read(supabaseProvider);
      await client.rpc<String>('mark_obligation_paid', params: {
        'p_occurrence_id': due['id'],
        'p_amount_minor': value,
        'p_paid_at': DateTime.now().toUtc().toIso8601String(),
        'p_payer_user_id': client.auth.currentUser!.id,
        'p_payment_source_id': null,
        'p_client_mutation_id': const Uuid().v4(),
      });
      ref.invalidate(recentExpensesProvider(widget.household.id));
      ref.invalidate(dashboardProvider(widget.household.id));
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment could not be recorded. Please retry.')));
      }
    }
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({this.expectedMinor});
  final int? expectedMinor;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final controller = TextEditingController(
      text: widget.expectedMinor == null
          ? ''
          : (widget.expectedMinor! / 100).toStringAsFixed(2));
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Record actual payment'),
        content: Form(
            key: form,
            child: TextFormField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount paid'),
                validator: (value) {
                  try {
                    Money.parseMinor(value ?? '');
                    return null;
                  } on FormatException {
                    return 'Enter a positive amount';
                  }
                })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, Money.parseMinor(controller.text));
                }
              },
              child: const Text('Record payment'))
        ],
      );
}
