import 'dates.dart';
import 'defaults.dart';
import 'model.dart';

// Port of the parts of src/core/ledger.ts the Android app uses (spec A-1).

/// ISO 8601 UTC with millisecond precision, exactly like JS `Date.toISOString()`;
/// timestamps are compared as strings across clients (vault-format §5.1).
String isoTimestamp(DateTime time) {
  final t = time.toUtc();
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return '${p(t.year, 4)}-${p(t.month)}-${p(t.day)}T${p(t.hour)}:${p(t.minute)}:${p(t.second)}.${p(t.millisecond, 3)}Z';
}

class TransactionInput {
  const TransactionInput({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.accountId,
    required this.date,
    required this.note,
  });

  final String type;
  final int amount;
  final String categoryId;
  final String accountId;
  final ISODate date;
  final String note;

  Json toJson() => {
        'type': type,
        'amount': amount,
        'categoryId': categoryId,
        'accountId': accountId,
        'date': date,
        'note': note,
      };
}

VaultData addTransactions(VaultData data, List<TransactionInput> inputs, [DateTime? now]) {
  if (inputs.isEmpty) return data;
  final ts = isoTimestamp(now ?? DateTime.now());
  return data.copyWith(transactions: [
    ...data.transactions,
    for (final input in inputs) Transaction({...input.toJson(), 'id': newId(), 'createdAt': ts, 'updatedAt': ts}),
  ]);
}

VaultData updateTransaction(VaultData data, String id, Json patch, [DateTime? now]) {
  final ts = isoTimestamp(now ?? DateTime.now());
  return data.copyWith(transactions: [
    for (final t in data.transactions) t.id == id ? t.copyWith({...patch, 'updatedAt': ts}) : t,
  ]);
}

List<Deletion> _withDeletion(VaultData data, String id, DateTime? now) => [
      for (final d in data.deletions) if (d.id != id) d,
      Deletion({'id': id, 'deletedAt': isoTimestamp(now ?? DateTime.now())}),
    ];

/// Removes the transaction and records a tombstone so sync drops it on other devices too.
VaultData deleteTransaction(VaultData data, String id, [DateTime? now]) {
  return data.copyWith(
    transactions: [for (final t in data.transactions) if (t.id != id) t],
    deletions: _withDeletion(data, id, now),
  );
}

VaultData upsertRecurring(VaultData data, RecurringRule rule, [DateTime? now]) {
  final stamped = RecurringRule({...rule.raw, 'updatedAt': isoTimestamp(now ?? DateTime.now())});
  final exists = data.recurring.any((r) => r.id == rule.id);
  return data.copyWith(recurring: [
    for (final r in data.recurring) r.id == rule.id ? stamped : r,
    if (!exists) stamped,
  ]);
}

/// Removes the rule only; transactions it generated are kept (F-REC-4).
VaultData deleteRecurring(VaultData data, String id, [DateTime? now]) {
  return data.copyWith(
    recurring: [for (final r in data.recurring) if (r.id != id) r],
    deletions: _withDeletion(data, id, now),
  );
}

/// Pauses or resumes a rule. Resuming skips occurrences that fell inside the paused
/// period, so a cancelled-then-restarted subscription is not back-filled (F-REC-4).
VaultData setRecurringActive(VaultData data, String id, bool active, ISODate today, [DateTime? now]) {
  final yesterday = addDays(today, -1);
  final updatedAt = isoTimestamp(now ?? DateTime.now());
  return data.copyWith(recurring: [
    for (final r in data.recurring)
      if (r.id != id)
        r
      else if (!active)
        RecurringRule({...r.raw, 'active': false, 'updatedAt': updatedAt})
      else
        RecurringRule({
          ...r.raw,
          'active': true,
          'lastGenerated': r.lastGenerated != null && r.lastGenerated!.compareTo(yesterday) > 0 ? r.lastGenerated : yesterday,
          'updatedAt': updatedAt,
        }),
  ]);
}

VaultData updateSettings(VaultData data, Json patch, [DateTime? now]) {
  return data.copyWith(
    settings: Settings({...data.settings.raw, ...patch, 'updatedAt': isoTimestamp(now ?? DateTime.now())}),
  );
}
