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

/// Removes the transaction and records a tombstone so sync drops it on other devices too.
VaultData deleteTransaction(VaultData data, String id, [DateTime? now]) {
  final deletedAt = isoTimestamp(now ?? DateTime.now());
  return data.copyWith(
    transactions: [for (final t in data.transactions) if (t.id != id) t],
    deletions: [
      for (final d in data.deletions) if (d.id != id) d,
      Deletion({'id': id, 'deletedAt': deletedAt}),
    ],
  );
}

VaultData updateSettings(VaultData data, Json patch, [DateTime? now]) {
  return data.copyWith(
    settings: Settings({...data.settings.raw, ...patch, 'updatedAt': isoTimestamp(now ?? DateTime.now())}),
  );
}
