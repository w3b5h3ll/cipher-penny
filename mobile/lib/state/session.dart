import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../core/defaults.dart';
import '../core/ledger.dart';
import '../core/merge.dart';
import '../core/model.dart';
import '../core/recurring.dart';
import '../core/validate.dart';
import '../crypto/vault_crypto.dart';
import '../remote/github.dart';
import '../storage/vault_store.dart';
import 'sync.dart';

// The unlocked vault and everything that touches secrets. Port of src/state/session.ts.
// The UI only talks to this class; it never sees the DEK, the envelope or the token.

const defaultSyncPath = 'vault.cpenny.json';
const _saveDebounce = Duration(milliseconds: 300);
const _syncDebounce = Duration(seconds: 10);
const _lockSyncWait = Duration(seconds: 5);
const _autoLockCheck = Duration(seconds: 10);

enum SessionStatus { loading, error, empty, locked, unlocked }

class SessionException implements Exception {
  const SessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the user sees about sync (F-SYNC-3).
class SyncView {
  const SyncView({
    required this.repo,
    required this.path,
    required this.syncing,
    required this.lastSyncedAt,
    required this.error,
    required this.foreign,
  });
  final String repo;
  final String path;
  final bool syncing;
  final String? lastSyncedAt;
  final String? error;

  /// The remote file belongs to another vault (F-SYNC-7).
  final bool foreign;
}

/// What the user types to set up sync (F-SYNC-1, F-SYNC-6).
class SyncSetup {
  const SyncSetup({required this.repo, required this.path, required this.token});
  final String repo;
  final String path;
  final String token;
}

class _SyncRecord {
  const _SyncRecord(this.target, this.cursor, this.lastSyncedAt);
  final GitHubTarget target;
  final SyncCursor cursor;
  final String? lastSyncedAt;

  Map<String, Object?> toJson() =>
      {'target': target.toJson(), 'cursor': cursor.toJson(), 'lastSyncedAt': lastSyncedAt};

  static _SyncRecord fromJson(Object? json) {
    final map = (json as Map).cast<String, Object?>();
    return _SyncRecord(
      GitHubTarget.fromJson((map['target'] as Map).cast()),
      SyncCursor.fromJson((map['cursor'] as Map).cast()),
      map['lastSyncedAt'] as String?,
    );
  }
}

String _errorText(Object err) => err.toString();

String _nowIso() => isoTimestamp(DateTime.now());

class Session extends ChangeNotifier {
  Session(this._store, {RemoteStore Function(GitHubTarget)? remoteFor, this.iterations = defaultIterations})
      : _remoteFor = remoteFor ?? GitHubRemote.new;

  final VaultStore _store;
  final RemoteStore Function(GitHubTarget) _remoteFor;
  final int iterations;

  SessionStatus _status = SessionStatus.loading;
  String? _errorMessage;
  VaultData? _data;
  int _recurringCreated = 0;
  String? _saveError;

  SessionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  int get recurringCreated => _recurringCreated;
  String? get saveError => _saveError;

  /// Plaintext data; only valid while unlocked.
  VaultData get data {
    final d = _data;
    if (_status != SessionStatus.unlocked || d == null) throw StateError('Vault is locked');
    return d;
  }

  // Secrets live only in these fields, and only while unlocked (F-VAULT-4, F-SYNC-8).
  Envelope? _envelope;
  SecretKey? _dek;
  _SyncRecord? _syncRecord;

  bool _dirty = false;
  Timer? _saveTimer;
  Future<void> _saveChain = Future.value();
  DateTime _lastActivity = DateTime.now();
  Timer? _autoLockTimer;

  Timer? _syncTimer;
  bool _syncPending = false;
  Future<void>? _syncRunning;
  bool _syncAgain = false;
  bool _syncing = false;
  String? _syncError;
  bool _syncForeign = false;

  SyncView? get sync {
    final record = _syncRecord;
    if (record == null) return null;
    return SyncView(
      repo: '${record.target.owner}/${record.target.repo}',
      path: record.target.path,
      syncing: _syncing,
      lastSyncedAt: record.lastSyncedAt,
      error: _syncError,
      foreign: _syncForeign,
    );
  }

  void _setData(VaultData data) {
    _data = data;
    notifyListeners();
  }

  // ---- Saving ----

  Future<void> _persist() async {
    final env = _envelope;
    final key = _dek;
    final data = _data;
    if (!_dirty || env == null || key == null || data == null || _status != SessionStatus.unlocked) return;
    _dirty = false;
    try {
      _envelope = await sealVault(env, key, data.raw);
      await _store.saveEnvelope(_envelope!);
      if (_saveError != null) {
        _saveError = null;
        notifyListeners();
      }
      _scheduleSync();
    } catch (err) {
      _dirty = true;
      _saveError = _errorText(err);
      notifyListeners();
    }
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(flush()));
  }

  /// Writes pending changes now. Saves are serialised so they land in order.
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveChain = _saveChain.then((_) => _persist());
    return _saveChain;
  }

  // ---- Sync (F-SYNC) ----

  void _resetSyncStatus() {
    _syncing = false;
    _syncError = null;
    _syncForeign = false;
  }

  void _cancelScheduledSync() {
    _syncTimer?.cancel();
    _syncPending = false;
  }

  void _scheduleSync() {
    if (_syncRecord == null) return;
    _syncTimer?.cancel();
    _syncPending = true;
    _syncTimer = Timer(_syncDebounce, () => unawaited(_requestSync()));
  }

  Future<void> _storeSyncRecord(SecretKey key, _SyncRecord record) async {
    await _store.saveSyncSecret(await encryptLocalSecret(key, record.toJson()));
  }

  /// Null if absent, or if it was written under another DEK.
  Future<_SyncRecord?> _loadSyncRecord(SecretKey key) async {
    final blob = await _store.loadSyncSecret();
    if (blob == null) return null;
    try {
      return _SyncRecord.fromJson(await decryptLocalSecret(key, blob));
    } catch (_) {
      await _store.deleteSyncSecret();
      return null;
    }
  }

  static GitHubTarget _toTarget(SyncSetup setup) {
    final repo = parseRepo(setup.repo);
    if (repo == null) throw const SessionException('仓库格式应为 owner/repo');
    final path = normalizePath(setup.path.trim().isEmpty ? defaultSyncPath : setup.path);
    if (path == null) throw const SessionException('文件路径无效');
    final token = setup.token.trim();
    if (token.isEmpty) throw const SessionException('请填写 GitHub 令牌');
    return GitHubTarget(owner: repo.owner, repo: repo.repo, path: path, token: token);
  }

  /// Runs sync rounds one at a time; a request during a round queues one more round.
  Future<void> _requestSync() {
    _cancelScheduledSync();
    if (_syncRecord == null || _status != SessionStatus.unlocked) return Future.value();
    final running = _syncRunning;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    final future = () async {
      try {
        do {
          _syncAgain = false;
          await _syncRound();
        } while (_syncAgain && _syncRecord != null && _status == SessionStatus.unlocked);
      } finally {
        _syncRunning = null;
      }
    }();
    _syncRunning = future;
    return future;
  }

  Future<void> _syncRound() async {
    await flush();
    _cancelScheduledSync();
    final record = _syncRecord;
    final key = _dek;
    final env = _envelope;
    final snapshot = _data;
    if (record == null || key == null || env == null || snapshot == null || _status != SessionStatus.unlocked) return;
    _syncing = true;
    notifyListeners();
    try {
      final result = await syncOnce(
        remote: _remoteFor(record.target),
        envelope: env,
        data: snapshot,
        dek: key,
        cursor: record.cursor,
      );
      // Locked, wiped or disconnected meanwhile: the next round redoes it.
      if (!identical(_dek, key) || !identical(_syncRecord, record)) return;
      if (result is SyncMerged) await _adoptMerged(result, snapshot);
      final localPayloadIv = switch (result) {
        SyncUnchanged() => record.cursor.localPayloadIv,
        SyncPushed(:final envelope) => envelope.payload.iv,
        SyncMerged(:final envelope) => envelope.payload.iv,
      };
      final next = _SyncRecord(
        record.target,
        SyncCursor(remoteSha: result.remoteSha, localPayloadIv: localPayloadIv),
        _nowIso(),
      );
      _syncRecord = next;
      _resetSyncStatus();
      await _storeSyncRecord(key, next);
    } catch (err) {
      _syncError = _errorText(err);
      _syncForeign = err is ForeignVaultException;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Takes the merged vault as the local copy, keeping edits made while the sync ran.
  Future<void> _adoptMerged(SyncMerged result, VaultData snapshot) {
    _saveChain = _saveChain.then((_) async {
      _envelope = result.envelope;
      await _store.saveEnvelope(result.envelope);
      final current = _data;
      if (_status != SessionStatus.unlocked || current == null) return;
      if (identical(current, snapshot)) {
        _setData(result.data);
      } else {
        _setData(mergeVaults(result.data, current));
        _scheduleSave();
      }
    });
    return _saveChain;
  }

  // ---- Lifecycle ----

  void _enterUnlocked(Envelope env, SecretKey key, VaultData data, _SyncRecord? record) {
    _envelope = env;
    _dek = key;
    _syncRecord = record;
    _resetSyncStatus();
    _data = data;
    _recurringCreated = 0;
    _saveError = null;
    _status = SessionStatus.unlocked;
    notifyListeners();
    _startBackgroundTasks();
    // Pull first so another device's back-fill or deletions are seen before we back-fill.
    if (record != null) {
      unawaited(_requestSync().whenComplete(_fillRecurring));
    } else {
      _fillRecurring();
    }
  }

  void _fillRecurring() {
    final current = _data;
    if (_status != SessionStatus.unlocked || current == null) return;
    final result = applyRecurring(current, todayISO());
    if (result.created == 0) return;
    _recurringCreated = result.created;
    _setData(result.data);
    _scheduleSave();
  }

  /// Call on user interaction; resets the auto-lock idle timer (spec A-3).
  void touch() => _lastActivity = DateTime.now();

  void _checkAutoLock() {
    final current = _data;
    if (_status != SessionStatus.unlocked || current == null) return;
    final minutes = current.settings.autoLockMinutes;
    if (minutes > 0 && DateTime.now().difference(_lastActivity) > Duration(minutes: minutes)) unawaited(lock());
  }

  /// App went to the background: save now and push pending changes.
  void onBackground() {
    unawaited(flush().then((_) => _syncPending ? _requestSync() : null));
  }

  /// App came back: lock if idle too long, otherwise pull remote changes.
  void onForeground() {
    _checkAutoLock();
    if (_status == SessionStatus.unlocked) unawaited(_requestSync());
  }

  void _startBackgroundTasks() {
    _lastActivity = DateTime.now();
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer.periodic(_autoLockCheck, (_) => _checkAutoLock());
  }

  void _stopBackgroundTasks() {
    _cancelScheduledSync();
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }

  void _dropSecrets() {
    _dek = null;
    _data = null;
    _syncRecord = null;
    _resetSyncStatus();
  }

  Future<void> init() async {
    try {
      _envelope = await _store.loadEnvelope();
      _status = _envelope == null ? SessionStatus.empty : SessionStatus.locked;
    } catch (err) {
      _errorMessage = _errorText(err);
      _status = SessionStatus.error;
    }
    notifyListeners();
  }

  /// F-VAULT-1
  Future<void> create(String password) async {
    final data = createDefaultVault();
    final created = await createVault(password, data.raw, iterations: iterations);
    await _store.deleteSyncSecret();
    await _store.saveEnvelope(created.envelope);
    _enterUnlocked(created.envelope, created.dek, data, null);
  }

  /// F-VAULT-2. Throws [WrongPasswordException] / [CorruptedVaultException].
  Future<void> unlock(String password) async {
    final env = _envelope;
    if (env == null) throw StateError('No vault');
    final opened = await openVault(env, password);
    final data = assertVaultData(opened.data);
    _enterUnlocked(env, opened.dek, data, await _loadSyncRecord(opened.dek));
  }

  /// Applies an immutable update and schedules an encrypted save.
  void update(VaultData Function(VaultData data) fn) {
    final current = _data;
    if (_status != SessionStatus.unlocked || current == null) return;
    final next = fn(current);
    if (identical(next, current)) return;
    _setData(next);
    _scheduleSave();
  }

  void clearRecurringNotice() {
    if (_recurringCreated == 0) return;
    _recurringCreated = 0;
    notifyListeners();
  }

  /// F-VAULT-4: drops plaintext, key and sync token from memory.
  Future<void> lock() async {
    if (_status != SessionStatus.unlocked) return;
    await flush();
    if (_syncPending || _syncRunning != null) {
      await Future.any([_requestSync(), Future<void>.delayed(_lockSyncWait)]);
    }
    if (_status != SessionStatus.unlocked) return;
    _stopBackgroundTasks();
    _dropSecrets();
    _status = SessionStatus.locked;
    notifyListeners();
  }

  /// F-VAULT-6
  Future<void> wipe() async {
    _saveTimer?.cancel();
    _dirty = false;
    await _saveChain;
    _stopBackgroundTasks();
    await _store.clearAll();
    _envelope = null;
    _dropSecrets();
    _status = SessionStatus.empty;
    notifyListeners();
  }

  // ---- Sync (F-SYNC) ----

  /// F-SYNC-1. Throws (with a user-facing message) if the repo is unusable.
  Future<void> connectSync(SyncSetup setup) async {
    final key = _dek;
    if (key == null || _status != SessionStatus.unlocked) throw StateError('Vault is locked');
    final target = _toTarget(setup);
    await _remoteFor(target).check();
    await _syncRunning;
    final record = _SyncRecord(target, const SyncCursor(), null);
    _syncRecord = record;
    await _storeSyncRecord(key, record);
    _resetSyncStatus();
    notifyListeners();
    await _requestSync();
  }

  /// F-SYNC-3: manual "sync now".
  Future<void> syncNow() => _requestSync();

  /// F-SYNC-8: forgets the local sync settings; the remote file is untouched.
  Future<void> disconnectSync() async {
    _cancelScheduledSync();
    _syncRecord = null;
    await _syncRunning;
    await _store.deleteSyncSecret();
    _resetSyncStatus();
    notifyListeners();
  }

  /// F-SYNC-7: replaces the remote file with the local vault.
  Future<void> overwriteRemote() async {
    await _syncRunning;
    final record = _syncRecord;
    final key = _dek;
    if (record == null || key == null) throw const SessionException('同步未开启');
    await flush();
    final local = _envelope;
    if (local == null) throw StateError('Vault is locked');
    final remote = _remoteFor(record.target);
    final existing = await remote.read();
    final remoteSha = await remote.write(serializeEnvelope(local), existing?.sha);
    if (!identical(_syncRecord, record)) return;
    final next = _SyncRecord(record.target, SyncCursor(remoteSha: remoteSha, localPayloadIv: local.payload.iv), _nowIso());
    _syncRecord = next;
    await _storeSyncRecord(key, next);
    _resetSyncStatus();
    notifyListeners();
  }

  /// F-SYNC-6: sets up this device from the remote vault. Throws
  /// [WrongPasswordException], or an error with a user-facing message, before
  /// touching local data.
  Future<void> restoreFromRemote(SyncSetup setup, String password) async {
    final target = _toTarget(setup);
    final remote = _remoteFor(target);
    await remote.check();
    final file = await remote.read();
    if (file == null) throw const SessionException('仓库里还没有同步文件，请先在已有数据的设备上开启同步');
    final Envelope remoteEnvelope;
    try {
      remoteEnvelope = parseEnvelope(jsonDecode(file.text));
    } on UnsupportedFormatException {
      rethrow;
    } on FormatException {
      throw const UnsupportedFormatException('同步文件不是有效的 CipherPenny 账本');
    }
    final opened = await openVault(remoteEnvelope, password);
    final data = assertVaultData(opened.data);
    await _store.saveEnvelope(remoteEnvelope);
    final record = _SyncRecord(
      target,
      SyncCursor(remoteSha: file.sha, localPayloadIv: remoteEnvelope.payload.iv),
      _nowIso(),
    );
    await _store.deleteSyncSecret();
    await _storeSyncRecord(opened.dek, record);
    _enterUnlocked(remoteEnvelope, opened.dek, data, record);
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _stopBackgroundTasks();
    super.dispose();
  }
}
