import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_management/src/core/data/providers.dart';
import 'package:home_management/src/core/domain/money.dart';
import 'package:home_management/src/features/household/domain/household.dart';
import 'package:home_management/src/features/spending/domain/expense.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:home_management/src/features/dashboard/presentation/today_screen.dart';
import 'expense_detail_screen.dart';
import 'package:home_management/src/core/presentation/managed_routes.dart';

final recentExpensesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  householdId,
) {
  return ref.watch(spendingRepositoryProvider).recent(householdId);
});

class SpendingScreen extends ConsumerWidget {
  const SpendingScreen({required this.household, super.key});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(recentExpensesProvider(household.id));
    if (!household.role.canReadLedger) {
      return _MemberSubmissionView(household: household, expenses: expenses);
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(recentExpensesProvider(household.id).future),
      child: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load spending: $error'),
            ),
          ],
        ),
        data: (rows) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: rows.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _MonthSummary(
                household: household,
                expenses: rows,
                onAnalytics: () => showAnalyticsSheet(context, ref, household),
              );
            }
            final row = rows[index - 1];
            final money = Money(
              row['total_minor'] as int,
              row['currency_code'] as String,
            );
            final amountLabel = Text(
              money.format(),
              style: Theme.of(context).textTheme.titleMedium,
            );
            return Card.filled(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                title: Text(row['summary'] as String),
                onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ExpenseDetailScreen(
                            expenseId: row['id'] as String,
                            household: household))),
                subtitle: Text(row['status'] as String),
                trailing: row['status'] == 'pending'
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.pending_actions),
                        onSelected: (decision) async {
                          if (decision == 'approve') {
                            await ref
                                .read(spendingRepositoryProvider)
                                .approve(row['id'] as String);
                          } else {
                            final reason = await _rejectionReason(context);
                            if (reason == null) return;
                            await ref
                                .read(spendingRepositoryProvider)
                                .reject(row['id'] as String, reason);
                          }
                          ref.invalidate(recentExpensesProvider(household.id));
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            enabled: false,
                            child: amountLabel,
                          ),
                          const PopupMenuItem(
                            value: 'approve',
                            child: Text('Approve'),
                          ),
                          const PopupMenuItem(
                            value: 'reject',
                            child: Text('Reject'),
                          ),
                        ],
                      )
                    : amountLabel,
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<String?> _rejectionReason(BuildContext context) async {
  final controller = TextEditingController();
  final value = await showManagedDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reject submission'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Reason'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Reject'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

class _MonthSummary extends ConsumerWidget {
  const _MonthSummary({
    required this.household,
    required this.expenses,
    required this.onAnalytics,
  });

  final Household household;
  final List<Map<String, dynamic>> expenses;
  final VoidCallback onAnalytics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider(household.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Spent this month'),
              const SizedBox(height: 6),
              Text(
                summary.when(
                  data: (data) => Money(data['spent_month_minor'] as int,
                          household.currencyCode)
                      .format(),
                  loading: () => 'Loading…',
                  error: (_, __) => 'Unavailable',
                ),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onAnalytics,
                icon: const Icon(Icons.insights),
                label: const Text('Explore trends'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AnalyticsPeriod { day, week, month, year }

Future<void> showAnalyticsSheet(
  BuildContext context,
  WidgetRef ref,
  Household household,
) async {
  var period = _AnalyticsPeriod.month;
  var anchor = DateTime.now();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final now = anchor;
        final from = switch (period) {
          _AnalyticsPeriod.day => DateTime(now.year, now.month, now.day),
          _AnalyticsPeriod.week => DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(Duration(days: now.weekday - 1)),
          _AnalyticsPeriod.month => DateTime(now.year, now.month),
          _AnalyticsPeriod.year => DateTime(now.year),
        };
        final until = switch (period) {
          _AnalyticsPeriod.day => from.add(const Duration(days: 1)),
          _AnalyticsPeriod.week => from.add(const Duration(days: 7)),
          _AnalyticsPeriod.month => DateTime(from.year, from.month + 1),
          _AnalyticsPeriod.year => DateTime(from.year + 1),
        };
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .75,
          maxChildSize: .95,
          builder: (context, controller) =>
              FutureBuilder<List<Map<String, dynamic>>>(
            future: ref
                .read(spendingRepositoryProvider)
                .analytics(household.id, from, until),
            builder: (context, snapshot) {
              final categoryTotals = <String, int>{};
              for (final row
                  in snapshot.data ?? const <Map<String, dynamic>>[]) {
                categoryTotals.update(
                  row['category_name'] as String,
                  (value) => value + row['total_minor'] as int,
                  ifAbsent: () => row['total_minor'] as int,
                );
              }
              final maximum = categoryTotals.values.fold<int>(
                1,
                (a, b) => a > b ? a : b,
              );
              final sortedCategories = categoryTotals.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  Text(
                    'Spending trends',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<_AnalyticsPeriod>(
                    segments: _AnalyticsPeriod.values
                        .map(
                          (value) => ButtonSegment(
                            value: value,
                            label: Text(value.name),
                          ),
                        )
                        .toList(),
                    selected: {period},
                    onSelectionChanged: (value) =>
                        setState(() => period = value.single),
                  ),
                  const SizedBox(height: 24),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                            tooltip: 'Previous period',
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() {
                                  anchor = switch (period) {
                                    _AnalyticsPeriod.day =>
                                      anchor.subtract(const Duration(days: 1)),
                                    _AnalyticsPeriod.week =>
                                      anchor.subtract(const Duration(days: 7)),
                                    _AnalyticsPeriod.month =>
                                      DateTime(anchor.year, anchor.month - 1),
                                    _AnalyticsPeriod.year =>
                                      DateTime(anchor.year - 1),
                                  };
                                })),
                        Text(from.toIso8601String().substring(0, 10)),
                        IconButton(
                            tooltip: 'Next period',
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() {
                                  anchor = switch (period) {
                                    _AnalyticsPeriod.day =>
                                      anchor.add(const Duration(days: 1)),
                                    _AnalyticsPeriod.week =>
                                      anchor.add(const Duration(days: 7)),
                                    _AnalyticsPeriod.month =>
                                      DateTime(anchor.year, anchor.month + 1),
                                    _AnalyticsPeriod.year =>
                                      DateTime(anchor.year + 1),
                                  };
                                })),
                      ]),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (categoryTotals.isEmpty)
                    const Text('No approved spending in this period.')
                  else
                    ...sortedCategories.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.key),
                                Text(
                                  Money(
                                    entry.value,
                                    household.currencyCode,
                                  ).format(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: entry.value / maximum,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}

class _MemberSubmissionView extends StatelessWidget {
  const _MemberSubmissionView({
    required this.household,
    required this.expenses,
  });

  final Household household;
  final AsyncValue<List<Map<String, dynamic>>> expenses;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.request_quote_rounded,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Submit household spending',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your submission stays private from other Members and enters the '
            'household ledger only after an Owner or Manager approves it.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Text('Your submissions',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...expenses.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (error, _) => [Text('Could not load submissions: $error')],
            data: (rows) => rows.isEmpty
                ? [const Text('No submissions yet.')]
                : rows.map(
                    (row) => Card.filled(
                      child: ListTile(
                        title: Text(row['summary'] as String),
                        subtitle: Text(row['status'] as String),
                        trailing: Text(
                          Money(
                            row['total_minor'] as int,
                            row['currency_code'] as String,
                          ).format(),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
}

Future<void> showQuickPurchaseSheet(
  BuildContext context,
  WidgetRef ref,
  Household household,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickPurchaseSheet(household: household),
    );

class _QuickPurchaseSheet extends ConsumerStatefulWidget {
  const _QuickPurchaseSheet({required this.household});
  final Household household;
  @override
  ConsumerState<_QuickPurchaseSheet> createState() =>
      _QuickPurchaseSheetState();
}

class _QuickPurchaseSheetState extends ConsumerState<_QuickPurchaseSheet> {
  final amount = TextEditingController();
  final item = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final mutationId = const Uuid().v4();
  bool busy = false;
  XFile? receipt;
  String? categoryId;
  List<Map<String, dynamic>> categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final values = await ref
          .read(spendingRepositoryProvider)
          .categories(widget.household.id);
      if (mounted) setState(() => categories = values);
    } catch (_) {
      // Category selection is optional; offline quick entry still works.
    }
  }

  @override
  void dispose() {
    amount.dispose();
    item.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final household = widget.household;
      final minor = Money.parseMinor(amount.text);
      final purchase = NewPurchase(
        clientMutationId: mutationId,
        householdId: household.id,
        summary: item.text.trim(),
        totalMinor: minor,
        currencyCode: household.currencyCode,
        incurredAt: DateTime.now(),
        payerUserId: ref.read(supabaseProvider).auth.currentUser!.id,
        categoryId: categoryId,
        items: [PurchaseItem(name: item.text.trim(), amountMinor: minor)],
      );
      final receiptBytes = await receipt?.readAsBytes();
      if (receiptBytes != null && receiptBytes.length > 1024 * 1024) {
        throw const FormatException(
            'Receipt photo exceeds 1 MB. Please retake it.');
      }
      final queue = ref.read(offlineCommandQueueProvider);
      await queue.enqueuePurchase(purchase, household.role,
          receiptBytes: receiptBytes);
      if (!await queue.isOffline) {
        await queue.synchronize();
      }
      ref.invalidate(recentExpensesProvider(household.id));
      ref.invalidate(dashboardProvider(household.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Saved. Pending work syncs automatically when connected.'),
        ));
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickReceipt() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 55,
        maxWidth: 1400,
        maxHeight: 1400,
      );
      if (selected != null && mounted) setState(() => receipt = selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Camera unavailable. Check camera permissions.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Quick purchase',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                TextFormField(
                  controller: amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Amount (${widget.household.currencyCode})',
                      prefixIcon: const Icon(Icons.payments_outlined)),
                  validator: (value) {
                    try {
                      Money.parseMinor(value ?? '');
                      return null;
                    } on FormatException {
                      return 'Enter a positive amount with up to two decimals';
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: item,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'What did you buy?',
                      prefixIcon: Icon(Icons.shopping_basket_outlined)),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter an item or short summary'
                      : null,
                  onFieldSubmitted: (_) => save(),
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: categories
                        .map((category) => DropdownMenuItem(
                              value: category['id'] as String,
                              child: Text(category['name'] as String),
                            ))
                        .toList(),
                    onChanged: (value) => categoryId = value,
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : pickReceipt,
                  icon: Icon(receipt == null
                      ? Icons.add_a_photo_outlined
                      : Icons.check_circle_outline),
                  label: Text(receipt == null
                      ? 'Add receipt photo'
                      : 'Receipt attached'),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: busy ? null : save,
                  icon: const Icon(Icons.check),
                  label: Text(busy
                      ? 'Saving…'
                      : widget.household.role.canReadLedger
                          ? 'Save purchase'
                          : 'Submit for approval'),
                ),
              ],
            )),
      );
}
