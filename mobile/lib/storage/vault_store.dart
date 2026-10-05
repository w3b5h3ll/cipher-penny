import 'dart:convert';
import 'dart:io';

import '../crypto/vault_crypto.dart';

// Ciphertext-only persistence in the app's private directory (spec A-4).
// Mirrors src/storage/idb.ts: one envelope plus the DEK-encrypted sync secret.

class VaultStore {
  VaultStore(this.directory);

  final Directory directory;

  File get _vaultFile => File('${directory.path}/vault.json');
  File get _syncFile => File('${directory.path}/sync.json');

  Future<Object?> _read(File file) async {
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  /// Write-then-rename so a crash mid-write never leaves a truncated vault.
  Future<void> _write(File file, Object? value) async {
    await directory.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _delete(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<Envelope?> loadEnvelope() async {
    final raw = await _read(_vaultFile);
    return raw == null ? null : parseEnvelope(raw);
  }

  Future<void> saveEnvelope(Envelope envelope) => _write(_vaultFile, envelope.raw);

  Future<CipherBlob?> loadSyncSecret() async {
    final raw = await _read(_syncFile);
    return raw is Map ? CipherBlob.fromJson(raw.cast()) : null;
  }

  Future<void> saveSyncSecret(CipherBlob blob) => _write(_syncFile, blob.toJson());

  Future<void> deleteSyncSecret() => _delete(_syncFile);

  Future<void> clearAll() async {
    await _delete(_vaultFile);
    await _delete(_syncFile);
  }
}
