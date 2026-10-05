import 'package:cipher_penny/core/dates.dart';
import 'package:cipher_penny/core/defaults.dart';
import 'package:cipher_penny/core/model.dart';
import 'package:cipher_penny/core/recurring.dart';
import 'package:cipher_penny/core/stats.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringRule rule([Json overrides = const {}]) => RecurringRule({
      'id': 'r1',
      'name': 'iCloud',
      'type': 'expense',
      'amount': 2100,
      'categoryId': 'c1',
      'accountId': 'a1',
      'note': '',
      'frequency': 'monthly',
      'interval': 1,
      'startDate': '2026-01-31',
      'active': true,
      ...overrides,
    });

VaultData vaultWith(RecurringRule r) => createDefaultVault().copyWith(recurring: [r]);

void main() {
  group('dates', () {
    test('addMonths clamps and keeps the anchor day', () {
      expect(addMonths('2026-01-31', 1), '2026-02-28');
      expect(addMonths('2026-02-28', 1, 31), '2026-03-31');
      expect(addMonths('2026-01-15', -1), '2025-12-15');
    });

    test('dayOfWeek uses 0 for Sunday', () {
      expect(dayOfWeek('2026-10-04'), 0);
      expect(dayOfWeek('2026-10-05'), 1);
    });
  });

  group('occurrencesBetween (F-REC-1, F-REC-3)', () {
    test('clamps monthly rules to month end and returns to the anchor day', () {
      expect(occurrencesBetween(rule(), null, '2026-05-01'), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
    });

    test('handles weekly rules with an interval', () {
      final r = rule({'frequency': 'weekly', 'interval': 2, 'startDate': '2026-09-07'});
      expect(occurrencesBetween(r, null, '2026-10-05'), ['2026-09-07', '2026-09-21', '2026-10-05']);
    });

    test('maps Feb 29 yearly rules to Feb 28 in common years', () {
      final r = rule({'frequency': 'yearly', 'startDate': '2028-02-29'});
      expect(occurrencesBetween(r, null, '2033-01-01'), ['2028-02-29', '2029-02-28', '2030-02-28', '2031-02-28', '2032-02-29']);
    });

    test('respects the exclusive lower bound and the end date', () {
      final r = rule({'startDate': '2026-01-15', 'endDate': '2026-04-14'});
      expect(occurrencesBetween(r, '2026-01-15', '2026-12-31'), ['2026-02-15', '2026-03-15']);
    });
  });

  group('applyRecurring (F-REC-2, F-REC-5)', () {
    test('back-fills with deterministic ids, like the web client', () {
      final result = applyRecurring(vaultWith(rule({'startDate': '2026-08-05'})), '2026-10-05', DateTime.utc(2026, 10, 7, 12));
      expect(result.created, 3);
      final tx = result.data.transactions.first;
      expect(tx.id, 'r1:2026-08-05');
      expect(tx.note, 'iCloud');
      expect(tx.createdAt, '2026-10-07T12:00:00.000Z');
      expect(tx.updatedAt, DateTime(2026, 8, 5).toUtc().toIso8601String());
      expect(result.data.recurring.first.lastGenerated, '2026-10-05');
    });

    test('is idempotent', () {
      final first = applyRecurring(vaultWith(rule({'startDate': '2026-08-05'})), '2026-10-05').data;
      final second = applyRecurring(first, '2026-10-05');
      expect(second.created, 0);
      expect(identical(second.data, first), isTrue);
    });

    test('does not duplicate when lastGenerated was lost', () {
      final first = applyRecurring(vaultWith(rule({'startDate': '2026-08-05'})), '2026-10-05').data;
      final reset = first.copyWith(recurring: [
        for (final r in first.recurring) RecurringRule({...r.raw}..remove('lastGenerated')),
      ]);
      expect(applyRecurring(reset, '2026-10-05').created, 0);
    });

    test('skips inactive rules', () {
      expect(applyRecurring(vaultWith(rule({'active': false, 'startDate': '2026-01-01'})), '2026-10-05').created, 0);
    });
  });

  group('stats', () {
    test('groups by day newest first and keeps only expenses', () {
      Transaction tx(String id, String date, String created, [String type = 'expense']) => Transaction({
            'id': id, 'type': type, 'amount': 100, 'categoryId': 'c', 'accountId': 'a',
            'date': date, 'note': '', 'createdAt': created, 'updatedAt': created,
          });
      final groups = groupByDate([
        tx('a', '2026-10-01', '2026-10-01T01:00:00.000Z'),
        tx('b', '2026-10-02', '2026-10-02T01:00:00.000Z'),
        tx('c', '2026-10-02', '2026-10-02T02:00:00.000Z'),
        tx('d', '2026-10-02', '2026-10-02T03:00:00.000Z', 'income'),
      ]);
      expect(groups.map((g) => g.date), ['2026-10-02', '2026-10-01']);
      expect(groups.first.items.map((t) => t.id), ['c', 'b']);
      expect(groups.first.total, 200);
      expect(daysElapsed('2026-10', '2026-10-05'), 5);
      expect(monthsElapsed(2025, '2026-10-05'), 12);
    });
  });
}
