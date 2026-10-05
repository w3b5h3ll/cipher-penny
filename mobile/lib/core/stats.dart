import 'dates.dart';
import 'model.dart';

// Port of src/core/stats.ts. Only expenses are counted (spec §2).

List<Transaction> expensesOf(Iterable<Transaction> txs) => [for (final t in txs) if (t.type == expense) t];

List<Transaction> transactionsInMonth(Iterable<Transaction> txs, MonthKey month) =>
    [for (final t in txs) if (monthKeyOf(t.date) == month) t];

List<Transaction> transactionsInYear(Iterable<Transaction> txs, int year) =>
    [for (final t in txs) if (t.date.startsWith('$year-')) t];

class Spending {
  const Spending(this.total, this.count);
  final int total;
  final int count;
}

Spending spending(Iterable<Transaction> txs) {
  var total = 0;
  var count = 0;
  for (final t in expensesOf(txs)) {
    total += t.amount;
    count += 1;
  }
  return Spending(total, count);
}

class MonthSpending extends Spending {
  const MonthSpending(this.month, super.total, super.count);
  final MonthKey month;
}

/// F-STAT-4: one entry per calendar month of `year`, empty months included.
List<MonthSpending> monthlySpending(Iterable<Transaction> txs, int year) {
  final byMonth = <MonthKey, List<Transaction>>{};
  for (final t in transactionsInYear(txs, year)) {
    byMonth.putIfAbsent(monthKeyOf(t.date), () => []).add(t);
  }
  return List.generate(12, (i) {
    final month = '$year-${(i + 1).toString().padLeft(2, '0')}';
    final s = spending(byMonth[month] ?? const []);
    return MonthSpending(month, s.total, s.count);
  });
}

int monthsElapsed(int year, ISODate today) {
  final currentYear = int.parse(today.substring(0, 4));
  if (year < currentYear) return 12;
  if (year > currentYear) return 0;
  return int.parse(today.substring(5, 7));
}

int daysElapsed(MonthKey month, ISODate today) {
  final current = monthKeyOf(today);
  final cmp = month.compareTo(current);
  if (cmp > 0) return 0;
  if (cmp < 0) return daysInMonth(int.parse(month.substring(0, 4)), int.parse(month.substring(5, 7)));
  return int.parse(today.substring(8, 10));
}

class GroupTotal {
  const GroupTotal(this.id, this.total, this.count, this.ratio);
  final String id;
  final int total;
  final int count;

  /// Share of total spending, 0..1
  final double ratio;
}

List<GroupTotal> _spendingBy(Iterable<Transaction> txs, String Function(Transaction) keyOf) {
  final totals = <String, (int, int)>{};
  var sum = 0;
  for (final t in expensesOf(txs)) {
    final key = keyOf(t);
    final (total, count) = totals[key] ?? (0, 0);
    totals[key] = (total + t.amount, count + 1);
    sum += t.amount;
  }
  final result = [
    for (final MapEntry(key: id, value: (total, count)) in totals.entries)
      GroupTotal(id, total, count, sum == 0 ? 0 : total / sum),
  ];
  mergeSort(result, (a, b) => b.total.compareTo(a.total));
  return result;
}

List<GroupTotal> spendingByCategory(Iterable<Transaction> txs) => _spendingBy(txs, (t) => t.categoryId);

List<GroupTotal> spendingByAccount(Iterable<Transaction> txs) => _spendingBy(txs, (t) => t.accountId);

class DayGroup {
  const DayGroup(this.date, this.items, this.total);
  final ISODate date;
  final List<Transaction> items;
  final int total;
}

/// Expenses grouped by date, newest day first; within a day, newest entry first.
List<DayGroup> groupByDate(Iterable<Transaction> txs) {
  final byDate = <ISODate, List<Transaction>>{};
  for (final t in expensesOf(txs)) {
    byDate.putIfAbsent(t.date, () => []).add(t);
  }
  final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      () {
        final items = byDate[date]!;
        mergeSort(items, (a, b) => b.createdAt.compareTo(a.createdAt));
        return DayGroup(date, items, spending(items).total);
      }(),
  ];
}

/// Stable sort (Dart's List.sort is not), matching JS Array.prototype.sort.
void mergeSort<T>(List<T> list, int Function(T a, T b) compare) {
  if (list.length < 2) return;
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}
