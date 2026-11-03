import 'dart:collection';

import '../repos/convoy_models.dart';

/// "A pays B 12.30": one transfer in a settle-up plan.
class Transfer {
  const Transfer({required this.from, required this.to, required this.cents});
  final String from;
  final String to;
  final int cents;

  @override
  bool operator ==(Object other) =>
      other is Transfer &&
      other.from == from &&
      other.to == to &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(from, to, cents);

  @override
  String toString() => '$from -> $to: $cents';
}

/// Expenses grouped by ISO currency, currencies in alphabetical order. Money
/// in different currencies is never added or netted against each other.
Map<String, List<ConvoyExpense>> byCurrency(List<ConvoyExpense> expenses) {
  final out = SplayTreeMap<String, List<ConvoyExpense>>();
  for (final e in expenses) {
    (out[e.currency] ??= []).add(e);
  }
  return out;
}

/// Total spent, per currency.
Map<String, int> totalsByCurrency(List<ConvoyExpense> expenses) => {
  for (final e in byCurrency(expenses).entries)
    e.key: e.value.fold(0, (a, x) => a + x.amountCents),
};

/// [balances], per currency.
Map<String, Map<String, int>> balancesByCurrency(
  List<ConvoyExpense> expenses,
  Set<String> participants,
) => {
  for (final e in byCurrency(expenses).entries)
    e.key: balances(e.value, participants),
};

/// [settleUp], per currency; currencies that are already square are left out.
Map<String, List<Transfer>> settleUpByCurrency(
  List<ConvoyExpense> expenses,
  Set<String> participants,
) {
  final out = <String, List<Transfer>>{};
  for (final e in balancesByCurrency(expenses, participants).entries) {
    final t = settleUp(e.value);
    if (t.isNotEmpty) out[e.key] = t;
  }
  return out;
}

/// Who paid what versus an equal split among [participants]. Positive balance
/// means the person is owed money. Pass expenses of one currency (see
/// [balancesByCurrency]).
Map<String, int> balances(
  List<ConvoyExpense> expenses,
  Set<String> participants,
) {
  if (participants.isEmpty) return const {};
  final result = {for (final p in participants) p: 0};
  final people = participants.toList()..sort();
  for (final e in expenses) {
    if (!participants.contains(e.payerId)) continue;
    result[e.payerId] = result[e.payerId]! + e.amountCents;
    // Split in whole cents; the first people alphabetically carry the remainder
    // so every expense sums exactly.
    final share = e.amountCents ~/ people.length;
    var remainder = e.amountCents - share * people.length;
    for (final p in people) {
      var owed = share;
      if (remainder > 0) {
        owed += 1;
        remainder -= 1;
      }
      result[p] = result[p]! - owed;
    }
  }
  return result;
}

/// Minimum cash flow: repeatedly match the largest debtor with the largest
/// creditor. At most n-1 transfers for n people.
List<Transfer> settleUp(Map<String, int> balance) {
  final creditors = <MapEntry<String, int>>[];
  final debtors = <MapEntry<String, int>>[];
  for (final e in balance.entries) {
    if (e.value > 0) creditors.add(MapEntry(e.key, e.value));
    if (e.value < 0) debtors.add(MapEntry(e.key, -e.value));
  }
  int byAmountDesc(MapEntry<String, int> a, MapEntry<String, int> b) {
    final c = b.value.compareTo(a.value);
    return c != 0 ? c : a.key.compareTo(b.key);
  }

  creditors.sort(byAmountDesc);
  debtors.sort(byAmountDesc);
  final out = <Transfer>[];
  var i = 0;
  var j = 0;
  var creditLeft = creditors.isEmpty ? 0 : creditors.first.value;
  var debtLeft = debtors.isEmpty ? 0 : debtors.first.value;
  while (i < creditors.length && j < debtors.length) {
    final amount = creditLeft < debtLeft ? creditLeft : debtLeft;
    if (amount > 0) {
      out.add(
        Transfer(from: debtors[j].key, to: creditors[i].key, cents: amount),
      );
    }
    creditLeft -= amount;
    debtLeft -= amount;
    if (creditLeft == 0) {
      i++;
      if (i < creditors.length) creditLeft = creditors[i].value;
    }
    if (debtLeft == 0) {
      j++;
      if (j < debtors.length) debtLeft = debtors[j].value;
    }
  }
  return out;
}

/// `$12.30` style, for USD; other currencies get the ISO code.
String formatCents(int cents, {String currency = 'USD'}) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final major = abs ~/ 100;
  final minor = (abs % 100).toString().padLeft(2, '0');
  return currency == 'USD'
      ? '$sign\$$major.$minor'
      : '$sign$major.$minor $currency';
}
