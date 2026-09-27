import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/domain/money.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:home_management/src/features/dashboard/presentation/today_screen.dart';
import 'spending_screen.dart';

class ExpenseDetailScreen extends ConsumerStatefulWidget {
  const ExpenseDetailScreen(
      {required this.expenseId, required this.household, super.key});
  final String expenseId;
  final Household household;
  @override
  ConsumerState<ExpenseDetailScreen> createState() =>
      _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends ConsumerState<ExpenseDetailScreen> {
  late Future<Map<String, dynamic>> _detail;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _detail = ref.read(spendingRepositoryProvider).detail(widget.expenseId);
  }

  Future<void> _change(Map<String, dynamic> row, bool voidOnly) async {
    final result = await showDialog<(String, int, String)>(
        context: context,
        builder: (_) => _CorrectionDialog(row: row, voidOnly: voidOnly));
    if (result == null) return;
    try {
      final repo = ref.read(spendingRepositoryProvider);
      if (voidOnly) {
        await repo.voidExpense(widget.expenseId, result.$3);
      } else {
        await repo.correctExpense(row, result.$1, result.$2, result.$3);
      }
      ref.invalidate(recentExpensesProvider(widget.household.id));
      ref.invalidate(dashboardProvider(widget.household.id));
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not update this expense. Reload if someone else changed it.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Expense details')),
        body: FutureBuilder<Map<String, dynamic>>(
            future: _detail,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: TextButton(
                        onPressed: () => setState(_reload),
                        child: const Text('Reload expense')));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final row = snapshot.data!;
              final receipt = row['receipt_path'] as String?;
              return ListView(padding: const EdgeInsets.all(24), children: [
                Text(row['summary'] as String,
                    style: Theme.of(context).textTheme.headlineSmall),
                Text(
                    Money(row['total_minor'] as int,
                            row['currency_code'] as String)
                        .format(),
                    style: Theme.of(context).textTheme.headlineMedium),
                Text(
                    '${row['status']} · ${DateTime.parse(row['incurred_at'] as String).toLocal()}'),
                if (row['note'] != null) Text(row['note'] as String),
                if (row['review_reason'] != null)
                  Text('Review: ${row['review_reason']}'),
                if (row['correction_reason'] != null)
                  Text('Correction: ${row['correction_reason']}'),
                const SizedBox(height: 16),
                for (final item in row['expense_items'] as List)
                  ListTile(
                      title: Text(item['name'] as String),
                      trailing: Text(Money(item['amount_minor'] as int,
                              row['currency_code'] as String)
                          .format())),
                if (receipt != null)
                  FutureBuilder<String>(
                      future: ref
                          .read(spendingRepositoryProvider)
                          .receiptUrl(receipt),
                      builder: (context, url) => url.hasData
                          ? Image.network(url.data!,
                              errorBuilder: (_, __, ___) =>
                                  const Text('Receipt could not load.'))
                          : const Text('Loading receipt…')),
                if (widget.household.role.canOperateHousehold &&
                    row['status'] == 'approved') ...[
                  const SizedBox(height: 24),
                  OutlinedButton(
                      onPressed: () => _change(row, false),
                      child: const Text('Correct expense')),
                  TextButton(
                      onPressed: () => _change(row, true),
                      child: const Text('Void expense')),
                ],
              ]);
            }),
      );
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({required this.row, required this.voidOnly});
  final Map<String, dynamic> row;
  final bool voidOnly;
  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  late final TextEditingController summary =
      TextEditingController(text: widget.row['summary'] as String);
  late final TextEditingController amount = TextEditingController(
      text: ((widget.row['total_minor'] as int) / 100).toStringAsFixed(2));
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    summary.dispose();
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.voidOnly ? 'Void expense' : 'Correct expense'),
        content: SingleChildScrollView(
            child: Form(
                key: form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (!widget.voidOnly) ...[
                    const Text(
                        'The item breakdown will be replaced by one summary item. The original remains in audit history.'),
                    TextFormField(
                        controller: summary,
                        decoration: const InputDecoration(labelText: 'Summary'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Summary required'
                                : null),
                    TextFormField(
                        controller: amount,
                        decoration: const InputDecoration(labelText: 'Amount'),
                        validator: (value) {
                          try {
                            Money.parseMinor(value ?? '');
                            return null;
                          } on FormatException {
                            return 'Enter a valid amount';
                          }
                        }),
                  ],
                  TextFormField(
                      controller: reason,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Reason required'
                              : null),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, (
                    summary.text.trim(),
                    Money.parseMinor(amount.text),
                    reason.text.trim()
                  ));
                }
              },
              child: Text(widget.voidOnly ? 'Void' : 'Save correction')),
        ],
      );
}
