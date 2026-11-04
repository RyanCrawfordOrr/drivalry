import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/convoy/settle_up.dart';
import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../widgets/friendly_error.dart';
import '../../../widgets/relative_time.dart';
import '../widgets/convoy_ui.dart';

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
    final split = participants.isEmpty
        ? 'Split among the cars in the convoy.'
        : 'Split ${participants.length} ways: '
              '${totals.isEmpty ? formatCents(0) : totals.entries.map(each).join(' + ')} each.';
    final totalEntries = totals.entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: ListView(
        padding: EdgeInsets.only(
          top: Space.lg,
          bottom: pageBottomInset(context),
        ),
        children: [
          Padding(
            padding: Space.screen,
            child: Reveal(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (totalEntries.isEmpty)
                    HeroNumber(kicker: 'Total', value: formatCents(0))
                  else
                    for (var i = 0; i < totalEntries.length; i++) ...[
                      if (i > 0) const SizedBox(height: Space.sm),
                      // One figure per currency: never added together.
                      HeroNumber(
                        kicker: i == 0 ? 'Total' : null,
                        value: formatCents(
                          totalEntries[i].value,
                          currency: totalEntries[i].key,
                        ),
                        small: i > 0,
                      ),
                    ],
                  const SizedBox(height: Space.xs),
                  Text(split, style: context.caption),
                  const SizedBox(height: Space.xl),
                  PrimaryButton(
                    key: const Key('add-expense'),
                    label: 'Add an expense',
                    icon: Icons.add,
                    onPressed: me == null ? null : () => _add(context, ref),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.section),
          if (transfers.isNotEmpty)
            EditorialSection(
              kicker: 'Settle up',
              child: Column(
                children: [
                  for (final c in transfers.entries)
                    for (final t in c.value)
                      ConvoyRow(
                        leading: const Icon(Icons.swap_horiz),
                        title:
                            '${nameOf[t.from] ?? 'Someone'} → '
                            '${nameOf[t.to] ?? 'someone'}',
                        titleStyle: context.body,
                        trailing: Text(
                          formatCents(t.cents, currency: c.key),
                          style: context.label,
                        ),
                      ),
                ],
              ),
            ),
          if (list.isNotEmpty && transfers.isEmpty)
            EditorialSection(
              kicker: 'Settle up',
              child: Text('All square.', style: context.bodyMuted),
            ),
          if (expenses.isLoading && list.isEmpty)
            const Padding(
              padding: Space.screen,
              child: Column(
                children: [
                  SkeletonTile(height: 64),
                  SizedBox(height: Space.md),
                  SkeletonTile(height: 64),
                ],
              ),
            ),
          if (!expenses.isLoading && list.isEmpty)
            // Follows the hero, which already ends with the section gap.
            const ConvoyNotice(
              headline: 'No expenses yet.',
              body:
                  'Gas, tolls, snacks, the motel: add it and the split works '
                  'itself out.',
              padding: EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.xxl,
              ),
            ),
          if (list.isNotEmpty)
            EditorialSection(
              kicker: 'Spent',
              child: Column(
                children: [
                  for (final (i, e) in list.reversed.indexed)
                    Reveal(
                      delay: Reveal.stagger(i),
                      child: _ExpenseRow(
                        expense: e,
                        mine: e.payerId == me,
                        payer: nameOf[e.payerId] ?? 'Someone',
                        now: now,
                        onRemove: () => ref
                            .read(convoyRepoProvider)
                            .deleteExpense(convoyId, e.id),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String label(String category) => switch (category) {
    'gas' => 'Gas',
    'tolls' => 'Tolls',
    'food' => 'Food',
    'lodging' => 'Lodging',
    _ => 'Other',
  };

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showConvoySheet<_NewExpense>(
      context,
      title: 'Add an expense',
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
      Haptics.success();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, doing: 'add that expense'))),
        );
      }
    }
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.mine,
    required this.payer,
    required this.now,
    required this.onRemove,
  });

  final ConvoyExpense expense;
  final bool mine;
  final String payer;
  final DateTime now;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = expense;
    final row = ConvoyRow(
      leading: Icon(expenseIcon(e.category), size: 28),
      title: e.note == null || e.note!.isEmpty
          ? ConvoyExpensesScreen.label(e.category)
          : e.note!,
      caption: '$payer · ${relativeTime(e.createdAt, now)}',
      trailing: Text(
        formatCents(e.amountCents, currency: e.currency),
        style: context.title.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    if (!mine) return row;
    return Dismissible(
      key: ValueKey('expense:${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.xl),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: Radii.tileRadius,
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        Haptics.warning();
        onRemove();
      },
      child: row,
    );
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final c in ConvoyExpense.categories)
                ChoiceChip(
                  avatar: Icon(expenseIcon(c), size: 18),
                  label: Text(ConvoyExpensesScreen.label(c)),
                  selected: _category == c,
                  onSelected: (_) {
                    Haptics.select();
                    setState(() => _category = c);
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: Space.lg),
          PrimaryButton(
            label: 'Add',
            onPressed: _cents == null
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(_NewExpense(_cents!, _category, _note.text)),
          ),
        ],
      ),
    );
  }
}
