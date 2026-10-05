import 'dates.dart';
import 'ledger.dart';
import 'model.dart';

// Port of src/core/recurring.ts. Generated ids and timestamps must match the web
// client exactly (vault-format §3), so two devices back-filling agree.

const _maxOccurrencesPerRun = 2000;

/// The n-th occurrence (0-based) of a rule, ignoring end date.
ISODate nthOccurrence(RecurringRule rule, int n) {
  final step = (rule.interval < 1 ? 1 : rule.interval) * n;
  final anchorDay = parseISODate(rule.startDate).day;
  switch (rule.frequency) {
    case 'weekly':
      return addDays(rule.startDate, 7 * step);
    case 'monthly':
      return addMonths(rule.startDate, step, anchorDay);
    case 'yearly':
      return addMonths(rule.startDate, 12 * step, anchorDay);
    default:
      throw ArgumentError('Unknown frequency ${rule.frequency}');
  }
}

/// Occurrences in (afterExclusive, untilInclusive], respecting the rule's end date.
List<ISODate> occurrencesBetween(RecurringRule rule, ISODate? afterExclusive, ISODate untilInclusive) {
  final end = rule.endDate;
  final limit = end != null && end.compareTo(untilInclusive) < 0 ? end : untilInclusive;
  final result = <ISODate>[];
  for (var n = 0; n < _maxOccurrencesPerRun * 10; n++) {
    final date = nthOccurrence(rule, n);
    if (date.compareTo(limit) > 0) break;
    if (afterExclusive == null || date.compareTo(afterExclusive) > 0) {
      result.add(date);
      if (result.length >= _maxOccurrencesPerRun) break;
    }
  }
  return result;
}

/// The next date this rule will generate a transaction for, or null when it has ended.
ISODate? nextOccurrence(RecurringRule rule, ISODate today) {
  final last = rule.lastGenerated;
  final floor = last != null && last.compareTo(today) >= 0 ? last : addDays(today, -1);
  final end = rule.endDate;
  for (var n = 0; n < 100000; n++) {
    final date = nthOccurrence(rule, n);
    if (end != null && date.compareTo(end) > 0) return null;
    if (date.compareTo(floor) > 0) return date;
  }
  return null;
}

String generatedTransactionId(String ruleId, ISODate date) => '$ruleId:$date';

/// Local midnight of the occurrence date, so a real edit or deletion always wins.
String _occurrenceTimestamp(ISODate date) {
  final d = parseISODate(date);
  return isoTimestamp(DateTime(d.year, d.month, d.day));
}

/// Generates transactions for every active rule up to and including `today` (F-REC-2).
/// Idempotent (F-REC-5). Returns the same object when nothing changed.
({VaultData data, int created}) applyRecurring(VaultData data, ISODate today, [DateTime? now]) {
  final existing = {
    for (final t in data.transactions)
      if (t.recurringId != null) '${t.recurringId}|${t.date}',
  };
  final ts = isoTimestamp(now ?? DateTime.now());
  final newTxs = <Transaction>[];
  var rulesChanged = false;

  final recurring = [
    for (final rule in data.recurring)
      () {
        if (!rule.active) return rule;
        final dates = occurrencesBetween(rule, rule.lastGenerated, today);
        if (dates.isEmpty) return rule;
        for (final date in dates) {
          if (!existing.add('${rule.id}|$date')) continue;
          newTxs.add(Transaction({
            'id': generatedTransactionId(rule.id, date),
            'type': rule.type,
            'amount': rule.amount,
            'categoryId': rule.categoryId,
            'accountId': rule.accountId,
            'date': date,
            'note': rule.note.isNotEmpty ? rule.note : rule.name,
            'createdAt': ts,
            'updatedAt': _occurrenceTimestamp(date),
            'recurringId': rule.id,
          }));
        }
        rulesChanged = true;
        return RecurringRule({...rule.raw, 'lastGenerated': dates.last});
      }(),
  ];

  if (!rulesChanged) return (data: data, created: 0);
  return (
    data: data.copyWith(recurring: recurring, transactions: [...data.transactions, ...newTxs]),
    created: newTxs.length,
  );
}
