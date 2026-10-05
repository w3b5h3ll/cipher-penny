import 'dart:convert';

import 'model.dart';

// Record-level merge (F-SYNC-4). Normative rules: docs/vault-format.md §5.1;
// cases: fixtures/merge-cases.json. Must give the same result as src/core/merge.ts.

/// `base` is the remote copy, `other` the local one.
VaultData mergeVaults(VaultData base, VaultData other) {
  final deletions = _mergeDeletions(base.deletions, other.deletions);
  final deletedAt = {for (final d in deletions) d.id: d.deletedAt};
  bool alive(VaultRecord r) {
    final at = deletedAt[r.id];
    return at == null || at.compareTo(r.updatedAt ?? '') < 0;
  }

  final merged = <String, Object?>{
    ...base.raw,
    for (final e in other.raw.entries)
      if (!base.raw.containsKey(e.key)) e.key: e.value,
    'accounts': [for (final r in _mergeById<Account>(base.accounts, other.accounts, _newer)) if (alive(r)) r.raw],
    'categories': [for (final r in _mergeById<Category>(base.categories, other.categories, _newer)) if (alive(r)) r.raw],
    'transactions': [
      for (final r in _dedupeGenerated([
        for (final t in _mergeById<Transaction>(base.transactions, other.transactions, _newer)) if (alive(t)) t,
      ]))
        r.raw,
    ],
    'recurring': [for (final r in _mergeById<RecurringRule>(base.recurring, other.recurring, _newerRule)) if (alive(r)) r.raw],
    'settings': _newerJson(base.settings.raw, other.settings.raw),
  };
  if (deletions.isNotEmpty) {
    merged['deletions'] = [for (final d in deletions) d.raw];
  } else {
    merged.remove('deletions');
  }
  return VaultData(merged);
}

/// Later `updatedAt` wins; ties are broken by serialized content so both sides agree.
Json _newerJson(Json a, Json b) {
  final ua = a['updatedAt'] as String? ?? '';
  final ub = b['updatedAt'] as String? ?? '';
  final c = ua.compareTo(ub);
  if (c != 0) return c > 0 ? a : b;
  return jsonEncode(a).compareTo(jsonEncode(b)) >= 0 ? a : b;
}

T _newer<T extends VaultRecord>(T a, T b) => identical(_newerJson(a.raw, b.raw), a.raw) ? a : b;

RecurringRule _newerRule(RecurringRule a, RecurringRule b) {
  final winner = _newer(a, b);
  final lastGenerated = _maxOptional(a.lastGenerated, b.lastGenerated);
  if (winner.lastGenerated == lastGenerated) return winner;
  return RecurringRule({...winner.raw, 'lastGenerated': lastGenerated});
}

String? _maxOptional(String? a, String? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.compareTo(b) > 0 ? a : b;
}

List<T> _mergeById<T extends VaultRecord>(List<T> base, List<T> other, T Function(T, T) pick) {
  final otherById = {for (final o in other) o.id: o};
  final baseIds = {for (final b in base) b.id};
  return [
    for (final b in base) otherById.containsKey(b.id) ? pick(b, otherById[b.id] as T) : b,
    for (final o in other) if (!baseIds.contains(o.id)) o,
  ];
}

List<Deletion> _mergeDeletions(List<Deletion> base, List<Deletion> other) {
  final byId = <String, Deletion>{};
  for (final d in [...base, ...other]) {
    final seen = byId[d.id];
    if (seen == null) {
      byId[d.id] = d;
    } else if (d.deletedAt.compareTo(seen.deletedAt) > 0) {
      byId[d.id] = Deletion({...seen.raw, 'deletedAt': d.deletedAt});
    }
  }
  return byId.values.toList();
}

/// One transaction per (recurringId, date): latest `updatedAt`, then smallest id.
List<Transaction> _dedupeGenerated(List<Transaction> txs) {
  final keep = <String, Transaction>{};
  for (final tx in txs) {
    final rid = tx.recurringId;
    if (rid == null) continue;
    final key = '$rid|${tx.date}';
    final kept = keep[key];
    final c = kept == null ? 1 : tx.updatedAt.compareTo(kept.updatedAt);
    if (kept == null || c > 0 || (c == 0 && tx.id.compareTo(kept.id) < 0)) keep[key] = tx;
  }
  return [
    for (final tx in txs)
      if (tx.recurringId == null || identical(keep['${tx.recurringId}|${tx.date}'], tx)) tx,
  ];
}
