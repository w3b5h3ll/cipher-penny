import 'dart:convert';
import 'dart:io';

import 'package:cipher_penny/core/dates.dart';
import 'package:cipher_penny/core/ledger.dart';
import 'package:cipher_penny/core/model.dart';
import 'package:cipher_penny/core/validate.dart';
import 'package:cipher_penny/crypto/vault_crypto.dart';
import 'package:cipher_penny/remote/github.dart';
import 'package:cipher_penny/state/session.dart';
import 'package:cipher_penny/state/sync.dart';
import 'package:cipher_penny/storage/vault_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for one file in a GitHub repo. Mirrors src/state/sync.test.ts.
class FakeRemote implements RemoteStore {
  RemoteFile? file;
  int writes = 0;
  bool isPrivate = true;
  final targets = <GitHubTarget>[];

  /// Runs once just before the next write, to simulate another device pushing first.
  void Function()? beforeWrite;
  int _counter = 0;

  String nextSha() => 'sha-${++_counter}';

  @override
  Future<void> check() async {
    if (!isPrivate) throw const RemoteException(RemoteErrorKind.publicRepo, '这是公开仓库');
  }

  @override
  Future<RemoteFile?> read() async => file;

  @override
  Future<String> write(String text, String? sha) async {
    final hook = beforeWrite;
    beforeWrite = null;
    hook?.call();
    if (file?.sha != sha) throw const RemoteException(RemoteErrorKind.conflict, 'stale');
    writes++;
    file = RemoteFile(nextSha(), text);
    return file!.sha;
  }
}

const password = 'pass-word-1';
const setup = SyncSetup(repo: 'paul/cipher-penny-data', path: '', token: 'github_pat_secret');

VaultData expenseOf(VaultData d, String note) => addTransactions(d, [
      TransactionInput(
        type: expense,
        amount: 1000,
        categoryId: d.categories.first.id,
        accountId: d.accounts.first.id,
        date: todayISO(),
        note: note,
      ),
    ]);

List<String> notes(VaultData d) => [for (final t in d.transactions) t.note]..sort();

void main() {
  late Directory dir;
  late FakeRemote fake;
  late VaultStore store;
  late Session session;

  Future<({Envelope envelope, VaultData data, dynamic dek})> readRemote([String pass = password]) async {
    final envelope = parseEnvelope(jsonDecode(fake.file!.text));
    final opened = await openVault(envelope, pass);
    return (envelope: envelope, dek: opened.dek, data: assertVaultData(opened.data));
  }

  Future<RemoteFile> otherDevicePush(VaultData Function(VaultData) edit) async {
    final remote = await readRemote();
    final sealed = await sealVault(remote.envelope, remote.dek, edit(remote.data).raw);
    return RemoteFile(fake.nextSha(), jsonEncode(sealed.raw));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cipher_penny_test');
    fake = FakeRemote();
    store = VaultStore(dir);
    session = Session(store, iterations: minIterations, remoteFor: (target) {
      fake.targets.add(target);
      return fake;
    });
    await session.init();
    await session.create(password);
  });

  tearDown(() async {
    await session.syncNow();
    await session.flush();
    session.dispose();
    await dir.delete(recursive: true);
  });

  test('persists only ciphertext and reopens with the password (F-VAULT-1/2)', () async {
    session.update((d) => expenseOf(d, '午饭'));
    await session.lock();
    expect(session.status, SessionStatus.locked);
    expect(File('${dir.path}/vault.json').readAsStringSync(), isNot(contains('午饭')));

    final reopened = Session(store, iterations: minIterations);
    await reopened.init();
    expect(reopened.status, SessionStatus.locked);
    await expectLater(reopened.unlock('nope'), throwsA(isA<WrongPasswordException>()));
    await reopened.unlock(password);
    expect(notes(reopened.data), ['午饭']);
    reopened.dispose();
  });

  test('first sync pushes; an unchanged second sync does not write (F-SYNC-1, F-SYNC-2)', () async {
    session.update((d) => expenseOf(d, '午饭'));
    await session.connectSync(setup);
    expect(fake.targets.first.toJson(),
        {'owner': 'paul', 'repo': 'cipher-penny-data', 'path': 'vault.cpenny.json', 'token': 'github_pat_secret'});
    expect(fake.writes, 1);
    expect(fake.file!.text, isNot(contains('午饭')));
    expect(notes((await readRemote()).data), ['午饭']);
    expect(session.sync!.repo, 'paul/cipher-penny-data');
    expect(session.sync!.error, isNull);
    expect(session.sync!.lastSyncedAt, isNotNull);

    await session.syncNow();
    expect(fake.writes, 1);
  });

  test('pushes local edits made after the last sync', () async {
    await session.connectSync(setup);
    session.update((d) => expenseOf(d, '晚饭'));
    await session.syncNow();
    expect(fake.writes, 2);
    expect(notes((await readRemote()).data), ['晚饭']);
  });

  test('merges edits from another device with local ones (F-SYNC-4)', () async {
    session.update((d) => expenseOf(d, '共同'));
    await session.connectSync(setup);
    final shared = session.data.transactions.first.id;
    fake.file = await otherDevicePush((d) => deleteTransaction(expenseOf(d, '远端'), shared));
    session.update((d) => expenseOf(d, '本机'));
    await session.syncNow();

    expect(notes(session.data), ['本机', '远端']);
    expect(notes((await readRemote()).data), ['本机', '远端']);
    await session.lock();
    await session.unlock(password);
    expect(notes(session.data), ['本机', '远端']);
  });

  test('pulls without writing when only the remote changed', () async {
    await session.connectSync(setup);
    fake.file = await otherDevicePush((d) => expenseOf(d, '远端'));
    await session.syncNow();
    expect(fake.writes, 1);
    expect(notes(session.data), ['远端']);
    await session.syncNow();
    expect(fake.writes, 1);
  });

  test('retries when another device pushes between read and write', () async {
    await session.connectSync(setup);
    final concurrent = await otherDevicePush((d) => expenseOf(d, '远端'));
    fake.beforeWrite = () => fake.file = concurrent;
    session.update((d) => expenseOf(d, '本机'));
    await session.syncNow();
    expect(session.sync!.error, isNull);
    expect(notes((await readRemote()).data), ['本机', '远端']);
    expect(notes(session.data), ['本机', '远端']);
  });

  test('stops on a remote file from another vault and can overwrite it (F-SYNC-7)', () async {
    final foreign = await createVault(password, {'schemaVersion': 1}, iterations: minIterations);
    fake.file = RemoteFile('foreign', jsonEncode(foreign.envelope.raw));
    session.update((d) => expenseOf(d, '本机'));
    await session.connectSync(setup);
    expect(session.sync!.foreign, isTrue);
    expect(session.sync!.error, contains('另一个账本'));
    expect(fake.writes, 0);

    await session.overwriteRemote();
    expect(session.sync!.foreign, isFalse);
    expect(session.sync!.error, isNull);
    expect(notes((await readRemote()).data), ['本机']);
  });

  test('adopts a password changed on another device (F-SYNC-5)', () async {
    await session.connectSync(setup);
    final remote = await readRemote();
    final rewrapped = await changePassword(remote.envelope, remote.dek, 'remote-new-pass', iterations: minIterations);
    fake.file = RemoteFile(fake.nextSha(), jsonEncode(rewrapped.raw));
    session.update((d) => expenseOf(d, '本机'));
    await session.syncNow();
    await session.lock();
    await expectLater(session.unlock(password), throwsA(isA<WrongPasswordException>()));
    await session.unlock('remote-new-pass');
    expect(notes(session.data), ['本机']);
    await readRemote('remote-new-pass');
  });

  test('restores a new device from the remote vault (F-SYNC-6)', () async {
    session.update((d) => expenseOf(d, '午饭'));
    await session.connectSync(setup);
    await session.lock();
    await session.wipe();
    expect(session.status, SessionStatus.empty);

    await expectLater(session.restoreFromRemote(setup, 'wrong-pass'), throwsA(isA<WrongPasswordException>()));
    expect(session.status, SessionStatus.empty);
    await session.restoreFromRemote(setup, password);
    expect(notes(session.data), ['午饭']);
    expect(session.sync!.repo, 'paul/cipher-penny-data');
    await session.syncNow();
    expect(fake.writes, 1);
  });

  test('pushes pending changes before locking', () async {
    await session.connectSync(setup);
    session.update((d) => expenseOf(d, '锁定前'));
    await session.lock();
    expect(notes((await readRemote()).data), ['锁定前']);
  });

  test('refuses public repos and invalid input (F-SYNC-1)', () async {
    fake.isPrivate = false;
    await expectLater(session.connectSync(setup),
        throwsA(isA<RemoteException>().having((e) => e.kind, 'kind', RemoteErrorKind.publicRepo)));
    expect(session.sync, isNull);
    await expectLater(session.connectSync(const SyncSetup(repo: 'nope', path: '', token: 't')),
        throwsA(predicate((e) => e.toString().contains('owner/repo'))));
    await expectLater(session.connectSync(const SyncSetup(repo: 'a/b', path: '../x', token: 't')),
        throwsA(predicate((e) => e.toString().contains('路径'))));
  });

  test('stores the token encrypted; disconnect forgets it (F-SYNC-8)', () async {
    await session.connectSync(setup);
    expect(fake.file!.text, isNot(contains('github_pat_secret')));
    expect(File('${dir.path}/vault.json').readAsStringSync(), isNot(contains('github_pat_secret')));
    expect(File('${dir.path}/sync.json').readAsStringSync(), isNot(contains('github_pat_secret')));

    await session.lock();
    await session.unlock(password);
    expect(session.sync!.repo, 'paul/cipher-penny-data');

    await session.disconnectSync();
    expect(session.sync, isNull);
    expect(await store.loadSyncSecret(), isNull);
    expect(fake.file, isNotNull);
  });
}
