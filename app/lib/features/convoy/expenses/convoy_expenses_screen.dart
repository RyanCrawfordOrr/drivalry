import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/convoy/settle_up.dart';
import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../widgets/relative_time.dart';

IconData expenseIcon(String category) => switch (category) {
  'gas' => Icons.local_gas_station_outlined,
  'tolls' => Icons.toll_outlined,
  'food' => Icons.restaurant_outlined,
  'lodging' => Icons.hotel_outlined,
  _ => Icons.receipt_long_outlined,
};

/// Shared costs: what everyone paid, split equally among the cars that are
/// in the convoy, and the fewest transfers that settle it.
class ConvoyExpensesScreen extends ConsumerWidget {
  const ConvoyExpensesScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserIdProvider);
    final expenses = ref.watch(convoyExpensesProvider(convoyId));
    final list = expenses.value ?? const <ConvoyExpense>[];
    final members =
        ref.watch(convoyMembersProvider(convoyId)).value ?? const [];
    final nameOf = {
      for (final m in members) m.userId: m.userId == me ? 'You' : m.name,
    };
    final participants = {
      for (final m in members)
        if (m.isPresent) m.userId,
      for (final e in list) e.payerId,
    };
    final totals = totalsByCurrency(list);
    final transfers = settleUpByCurrency(list, participants);
    final now = DateTime.now().toUtc();
    String each(MapEntry<String, int> t) => formatCents(
      participants.isEmpty ? 0 : t.value ~/ participants.length,
      currency: t.key,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-expense'),
        onPressed: me == null ? null : () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (totals.isEmpty)
                    Text(
                      'Total ${formatCents(0)}',
                      style: theme.textTheme.titleLarge,
                    ),
                  // One line per currency: different currencies are never
                  // added together.
                  for (final t in totals.entries)
                    Text(
                      'Total ${formatCents(t.value, currency: t.key)}',
                      style: theme.textTheme.titleLarge,
                    ),
                  Text(
                    participants.isEmpty
                        ? 'Split among the cars in the convoy.'
                        : 'Split ${participants.length} ways: '
                              '${totals.isEmpty ? formatCents(0) : totals.entries.map(each).join(' + ')} each.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (transfers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Settle up', style: theme.textTheme.titleSmall),
                    for (final c in transfers.entries)
                      for (final t in c.value)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${nameOf[t.from] ?? 'Someone'} → '
                            '${nameOf[t.to] ?? 'someone'}: '
                            '${formatCents(t.cents, currency: c.key)}',
                          ),
                        ),
                  ],
                  if (list.isNotEmpty && transfers.isEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('All square.'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (expenses.isLoading && list.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (!expenses.isLoading && list.isEmpty)
            Text(
              'Nothing added yet. Gas, tolls, snacks, the motel: add it and '
              'the split works itself out.',
              style: theme.textTheme.bodyMedium,
            ),
          for (final e in list.reversed)
            Dismissible(
              key: ValueKey('expense:${e.id}'),
              direction: e.payerId == me
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: theme.colorScheme.errorContainer,
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) =>
                  ref.read(convoyRepoProvider).deleteExpense(convoyId, e.id),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(expenseIcon(e.category)),
                title: Text(
                  e.note == null || e.note!.isEmpty
                      ? _label(e.category)
                      : e.note!,
                ),
                subtitle: Text(
                  '${nameOf[e.payerId] ?? 'Someone'} · '
                  '${relativeTime(e.createdAt, now)}',
                ),
                trailing: Text(
                  formatCents(e.amountCents, currency: e.currency),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _label(String category) => switch (category) {
    'gas' => 'Gas',
    'tolls' => 'Tolls',
    'food' => 'Food',
    'lodging' => 'Lodging',
    _ => 'Other',
  };

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_NewExpense>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddExpenseSheet(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(convoyRepoProvider)
          .addExpense(
            convoyId,
            amountCents: result.cents,
            category: result.category,
            note: result.note,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }
}

class _NewExpense {
  const _NewExpense(this.cents, this.category, this.note);
  final int cents;
  final String category;
  final String? note;
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet();

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _category = 'gas';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _cents {
    final v = double.tryParse(_amount.text.replaceAll(',', '.').trim());
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add an expense', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('expense-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: r'$ ',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final c in ConvoyExpense.categories)
                ChoiceChip(
                  avatar: Icon(expenseIcon(c), size: 18),
                  label: Text(ConvoyExpensesScreen._label(c)),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _cents == null
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(_NewExpense(_cents!, _category, _note.text)),
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }
}
