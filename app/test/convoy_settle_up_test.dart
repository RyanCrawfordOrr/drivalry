import 'package:drivalry/data/convoy/settle_up.dart';
import 'package:drivalry/data/repos/convoy_models.dart';
import 'package:flutter_test/flutter_test.dart';

ConvoyExpense _e(String id, String payer, int cents) => ConvoyExpense(
  id: id,
  convoyId: 'c',
  payerId: payer,
  amountCents: cents,
  category: 'gas',
  createdAt: DateTime.utc(2026, 11, 3),
);

void main() {
  group('balances', () {
    test('equal split; payer is owed the rest', () {
      final b = balances([_e('1', 'a', 3000)], {'a', 'b', 'c'});
      expect(b, {'a': 2000, 'b': -1000, 'c': -1000});
    });

    test('odd cents land on the first people alphabetically', () {
      final b = balances([_e('1', 'b', 1000)], {'a', 'b', 'c'});
      // 1000 / 3 = 333 r1: a pays 334, b and c 333.
      expect(b['a'], -334);
      expect(b['b'], 1000 - 333);
      expect(b['c'], -333);
      expect(b.values.reduce((x, y) => x + y), 0);
    });

    test('expenses by non-participants are ignored', () {
      final b = balances([_e('1', 'zed', 500)], {'a', 'b'});
      expect(b, {'a': 0, 'b': 0});
    });

    test('empty participants', () {
      expect(balances([_e('1', 'a', 100)], {}), isEmpty);
    });
  });

  group('settleUp', () {
    test('one payer, two debtors', () {
      final t = settleUp({'a': 2000, 'b': -1000, 'c': -1000});
      expect(t, [
        const Transfer(from: 'b', to: 'a', cents: 1000),
        const Transfer(from: 'c', to: 'a', cents: 1000),
      ]);
    });

    test('n-1 transfers at most and everything nets to zero', () {
      final balance = {'a': 500, 'b': 700, 'c': -300, 'd': -900};
      final t = settleUp(balance);
      expect(t.length, lessThanOrEqualTo(3));
      final net = Map<String, int>.from(balance);
      for (final x in t) {
        net[x.from] = net[x.from]! + x.cents;
        net[x.to] = net[x.to]! - x.cents;
      }
      expect(net.values.every((v) => v == 0), isTrue);
    });

    test('already settled', () {
      expect(settleUp({'a': 0, 'b': 0}), isEmpty);
    });
  });

  test('formatCents', () {
    expect(formatCents(1230), r'$12.30');
    expect(formatCents(-5), r'-$0.05');
    expect(formatCents(1000, currency: 'EUR'), '10.00 EUR');
  });

  group('by currency', () {
    ConvoyExpense eur(String id, String payer, int cents) => ConvoyExpense(
      id: id,
      convoyId: 'c',
      payerId: payer,
      amountCents: cents,
      category: 'food',
      currency: 'EUR',
      createdAt: DateTime.utc(2026, 11, 3),
    );

    test('totals, balances and transfers never mix currencies', () {
      final list = [_e('1', 'a', 3000), eur('2', 'b', 2000)];
      expect(totalsByCurrency(list), {'EUR': 2000, 'USD': 3000});
      final b = balancesByCurrency(list, {'a', 'b'});
      expect(b['USD'], {'a': 1500, 'b': -1500});
      expect(b['EUR'], {'a': -1000, 'b': 1000});
      final t = settleUpByCurrency(list, {'a', 'b'});
      expect(t['USD'], [const Transfer(from: 'b', to: 'a', cents: 1500)]);
      expect(t['EUR'], [const Transfer(from: 'a', to: 'b', cents: 1000)]);
    });

    test('square currencies are left out; nothing in, nothing out', () {
      final list = [_e('1', 'a', 1000), _e('2', 'b', 1000)];
      expect(settleUpByCurrency(list, {'a', 'b'}), isEmpty);
      expect(totalsByCurrency(const []), isEmpty);
      expect(balancesByCurrency(const [], {'a'}), isEmpty);
    });
  });
}
