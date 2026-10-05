import 'dart:convert';

import 'package:cipher_penny/core/defaults.dart';
import 'package:cipher_penny/core/ledger.dart';
import 'package:cipher_penny/core/merge.dart';
import 'package:cipher_penny/core/model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';

/// Fills the fields the fixture omits (see fixture description).
Json complete(Object? partial) => {
      'schemaVersion': 1,
      'accounts': <Object?>[],
      'categories': <Object?>[],
      'transactions': <Object?>[],
      'recurring': <Object?>[],
      'settings': {'autoLockMinutes': 5},
      'deletions': <Object?>[],
      ...(partial as Map).cast<String, Object?>(),
    };

Json canonical(VaultData d) {
  List<Object?> sorted(String key) =>
      [...(d.raw[key] as List? ?? const [])]..sort((a, b) => ((a as Map)['id'] as String).compareTo((b as Map)['id'] as String));
  return {
    ...d.raw,
    for (final key in ['accounts', 'categories', 'transactions', 'recurring', 'deletions']) key: sorted(key),
  };
}

void main() {
  group('mergeVaults — fixtures/merge-cases.json (F-SYNC-4)', () {
    final fixture = loadFixture('merge-cases.json');
    for (final c in (fixture['cases'] as List).cast<Map<String, Object?>>()) {
      test(c['name'] as String, () {
        final merged = mergeVaults(VaultData(complete(c['base'])), VaultData(complete(c['other'])));
        expect(complete(merged.raw), complete(c['expected']));
      });
    }
  });

  group('mergeVaults properties', () {
    final t0 = DateTime.utc(2026, 10, 1);
    final t1 = DateTime.utc(2026, 10, 2);
    final t2 = DateTime.utc(2026, 10, 3);

    ({VaultData remote, VaultData local, String firstId}) diverged() {
      final vault = createDefaultVault();
      TransactionInput input(String note) => TransactionInput(
            type: expense,
            amount: 1000,
            categoryId: vault.categories.first.id,
            accountId: vault.accounts.first.id,
            date: '2026-10-01',
            note: note,
          );
      final common = addTransactions(vault, [input('共同一'), input('共同二')], t0);
      final first = common.transactions[0];
      final second = common.transactions[1];
      final remote = deleteTransaction(addTransactions(common, [input('远端新增')], t1), first.id, t1);
      final local = updateTransaction(addTransactions(common, [input('本机新增')], t1), second.id, {'amount': 1, 'note': '本机改'}, t2);
      return (remote: remote, local: local, firstId: first.id);
    }

    test('combines independent edits from both devices', () {
      final d = diverged();
      final merged = mergeVaults(d.remote, d.local);
      expect(merged.transactions.map((t) => t.note), ['本机改', '远端新增', '本机新增']);
      expect(merged.deletions.single.id, d.firstId);
    });

    test('produces the same content regardless of argument order', () {
      final d = diverged();
      expect(canonical(mergeVaults(d.remote, d.local)), canonical(mergeVaults(d.local, d.remote)));
    });

    test('is idempotent and omits empty deletions', () {
      final vault = createDefaultVault();
      final merged = mergeVaults(vault, vault);
      expect(jsonEncode(merged.raw), jsonEncode(vault.raw));
      expect(merged.raw.containsKey('deletions'), isFalse);
      final d = diverged();
      final once = mergeVaults(d.remote, d.local);
      expect(jsonEncode(mergeVaults(once, d.local).raw), jsonEncode(once.raw));
    });
  });

  test('isoTimestamp matches JS Date.toISOString()', () {
    expect(isoTimestamp(DateTime.utc(2026, 10, 5, 4, 3, 2, 1, 999)), '2026-10-05T04:03:02.001Z');
  });
}
