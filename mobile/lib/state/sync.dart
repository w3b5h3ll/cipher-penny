import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../core/merge.dart';
import '../core/model.dart';
import '../core/validate.dart';
import '../crypto/vault_crypto.dart';
import '../remote/github.dart';

// One sync round (F-SYNC-4, F-SYNC-5, F-SYNC-7). Port of src/state/sync.ts.
// Normative rules: docs/vault-format.md §5.

abstract class RemoteStore {
  Future<void> check();
  Future<RemoteFile?> read();
  Future<String> write(String text, String? sha);
}

class GitHubRemote implements RemoteStore {
  GitHubRemote(GitHubTarget target) : _client = GitHubClient(target);
  final GitHubClient _client;
  @override
  Future<void> check() => _client.checkRepo();
  @override
  Future<RemoteFile?> read() => _client.readFile();
  @override
  Future<String> write(String text, String? sha) => _client.writeFile(text, sha);
}

/// What we knew after the last successful sync; persisted per device.
class SyncCursor {
  const SyncCursor({this.remoteSha, this.localPayloadIv, this.keyChanged = false});
  factory SyncCursor.fromJson(Map<String, Object?> json) => SyncCursor(
        remoteSha: json['remoteSha'] as String?,
        localPayloadIv: json['localPayloadIv'] as String?,
        keyChanged: json['keyChanged'] == true,
      );

  /// Blob sha of the remote file right after the last sync.
  final String? remoteSha;

  /// Payload IV of the local envelope right after the last sync. Every save uses a
  /// fresh random IV, so a different value means local data changed.
  final String? localPayloadIv;

  /// The password was changed on this device since the last sync (vault-format §5.2).
  final bool keyChanged;

  Map<String, Object?> toJson() => {'remoteSha': remoteSha, 'localPayloadIv': localPayloadIv, 'keyChanged': keyChanged};
}

sealed class SyncResult {
  const SyncResult(this.remoteSha);
  final String remoteSha;
}

class SyncUnchanged extends SyncResult {
  const SyncUnchanged(super.remoteSha);
}

class SyncPushed extends SyncResult {
  const SyncPushed(super.remoteSha, this.envelope);
  final Envelope envelope;
}

/// Remote had changes; the caller must adopt [envelope] and [data] locally.
class SyncMerged extends SyncResult {
  const SyncMerged(super.remoteSha, this.envelope, this.data);
  final Envelope envelope;
  final VaultData data;
}

class ForeignVaultException implements Exception {
  const ForeignVaultException();
  @override
  String toString() => '远端文件无法用本机的密钥解密：它属于另一个账本，或者已损坏';
}

const _maxAttempts = 3;

String serializeEnvelope(Envelope envelope) => '${const JsonEncoder.withIndent('  ').convert(envelope.raw)}\n';

Future<SyncResult> syncOnce({
  required RemoteStore remote,
  required Envelope envelope,
  required VaultData data,
  required SecretKey dek,
  required SyncCursor cursor,
  DateTime Function()? now,
}) async {
  for (var attempt = 1;; attempt++) {
    try {
      return await _attemptSync(remote, envelope, data, dek, cursor, now ?? DateTime.now);
    } on RemoteException catch (e) {
      if (e.kind != RemoteErrorKind.conflict || attempt >= _maxAttempts) rethrow;
    }
  }
}

Future<SyncResult> _attemptSync(
  RemoteStore remote,
  Envelope envelope,
  VaultData data,
  SecretKey dek,
  SyncCursor cursor,
  DateTime Function() now,
) async {
  final file = await remote.read();
  if (file == null) {
    return SyncPushed(await remote.write(serializeEnvelope(envelope), null), envelope);
  }

  if (file.sha == cursor.remoteSha) {
    if (envelope.payload.iv == cursor.localPayloadIv && !cursor.keyChanged) return SyncUnchanged(file.sha);
    return SyncPushed(await remote.write(serializeEnvelope(envelope), file.sha), envelope);
  }

  final remoteEnvelope = _decodeRemote(file);
  final remoteData = await _openRemote(remoteEnvelope, dek);
  final merged = mergeVaults(remoteData, data);
  if (!cursor.keyChanged && jsonEncode(merged.raw) == jsonEncode(remoteData.raw)) {
    return SyncMerged(file.sha, remoteEnvelope, remoteData);
  }
  final keys = cursor.keyChanged ? envelope : remoteEnvelope;
  final sealed = await sealVault(
    envelope.copyWith({'kdf': keys.raw['kdf'], 'wrappedKey': keys.raw['wrappedKey']}),
    dek,
    merged.raw,
    now(),
  );
  final remoteSha = await remote.write(serializeEnvelope(sealed), file.sha);
  return SyncMerged(remoteSha, sealed, merged);
}

Envelope _decodeRemote(RemoteFile file) {
  try {
    return parseEnvelope(jsonDecode(file.text));
  } on Exception {
    throw const ForeignVaultException();
  }
}

Future<VaultData> _openRemote(Envelope envelope, SecretKey dek) async {
  try {
    return assertVaultData(await openPayload(envelope, dek));
  } on Exception {
    throw const ForeignVaultException();
  }
}
