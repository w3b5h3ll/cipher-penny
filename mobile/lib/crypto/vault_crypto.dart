import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../core/ledger.dart' show isoTimestamp;
import '../core/model.dart';

// Normative spec: docs/vault-format.md §1–2. Same envelope as src/crypto/vault-crypto.ts.
// `Pbkdf2` and `AesGcm` resolve to Android's native implementations once
// FlutterCryptography is enabled (spec A-5), and to pure Dart in tests.

const vaultFormat = 'cipher-penny-vault';
const vaultVersion = 1;
const defaultIterations = 600000;
const minIterations = 100000;
const _maxIterations = 10000000;
const _saltBytes = 16;
const _tagBytes = 16;
final _aadDek = utf8.encode('cipher-penny:v1:dek');
final _aadPayload = utf8.encode('cipher-penny:v1:payload');
final _aadLocalSecret = utf8.encode('cipher-penny:v1:local-secret');

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => '密码错误';
}

class CorruptedVaultException implements Exception {
  const CorruptedVaultException([this.message = '数据已损坏或被篡改，无法解密']);
  final String message;
  @override
  String toString() => message;
}

class UnsupportedFormatException implements Exception {
  const UnsupportedFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CipherBlob {
  const CipherBlob(this.iv, this.data);
  factory CipherBlob.fromJson(Json json) => CipherBlob(json['iv'] as String, json['data'] as String);
  final String iv;
  final String data;
  Json toJson() => {'iv': iv, 'data': data};
}

/// The encrypted vault as stored locally, in backups and in the sync repo.
class Envelope {
  const Envelope(this.raw);
  final Json raw;

  Json get kdf => (raw['kdf'] as Map).cast<String, Object?>();
  int get iterations => (kdf['iterations'] as num).toInt();
  String get salt => kdf['salt'] as String;
  CipherBlob get wrappedKey => CipherBlob.fromJson((raw['wrappedKey'] as Map).cast());
  CipherBlob get payload => CipherBlob.fromJson((raw['payload'] as Map).cast());
  String get updatedAt => raw['updatedAt'] as String;

  Envelope copyWith(Json patch) => Envelope({...raw, ...patch});
}

final _aes = AesGcm.with256bits();

Future<SecretKey> _deriveKek(String password, List<int> salt, int iterations) {
  final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
  return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
}

Future<CipherBlob> _encrypt(SecretKey key, List<int> plaintext, List<int> aad) async {
  final nonce = _aes.newNonce();
  final box = await _aes.encrypt(plaintext, secretKey: key, nonce: nonce, aad: aad);
  return CipherBlob(base64Encode(nonce), base64Encode([...box.cipherText, ...box.mac.bytes]));
}

/// Throws [SecretBoxAuthenticationError] if the key, IV, AAD or ciphertext is wrong.
Future<List<int>> _decrypt(SecretKey key, CipherBlob blob, List<int> aad) {
  final bytes = base64Decode(blob.data);
  if (bytes.length < _tagBytes) throw SecretBoxAuthenticationError();
  final box = SecretBox(
    bytes.sublist(0, bytes.length - _tagBytes),
    nonce: base64Decode(blob.iv),
    mac: Mac(bytes.sublist(bytes.length - _tagBytes)),
  );
  return _aes.decrypt(box, secretKey: key, aad: aad);
}

Future<Object?> _decryptJson(SecretKey key, CipherBlob blob, List<int> aad) async {
  final List<int> plaintext;
  try {
    plaintext = await _decrypt(key, blob, aad);
  } on SecretBoxAuthenticationError {
    throw const CorruptedVaultException();
  }
  try {
    return jsonDecode(utf8.decode(plaintext));
  } on FormatException {
    throw const CorruptedVaultException('解密后的数据不是有效的 JSON');
  }
}

Future<CipherBlob> _encryptJson(SecretKey key, Object? value, List<int> aad) =>
    _encrypt(key, utf8.encode(jsonEncode(value)), aad);

Future<Json> _wrapDek(SecretKey dek, String password, int iterations) async {
  final salt = SecretKeyData.random(length: _saltBytes).bytes;
  final kek = await _deriveKek(password, salt, iterations);
  final wrapped = await _encrypt(kek, await dek.extractBytes(), _aadDek);
  return {
    'kdf': {'name': 'PBKDF2', 'hash': 'SHA-256', 'iterations': iterations, 'salt': base64Encode(salt)},
    'wrappedKey': wrapped.toJson(),
  };
}

/// Creates a new vault with a fresh random DEK (F-VAULT-1, F-VAULT-3).
Future<({Envelope envelope, SecretKey dek})> createVault(String password, Object? data,
    {int iterations = defaultIterations, DateTime? now}) async {
  final dek = SecretKeyData.random(length: 32);
  final envelope = Envelope({
    'format': vaultFormat,
    'version': vaultVersion,
    ...await _wrapDek(dek, password, iterations),
    'payload': (await _encryptJson(dek, data, _aadPayload)).toJson(),
    'updatedAt': isoTimestamp(now ?? DateTime.now()),
  });
  return (envelope: envelope, dek: dek);
}

/// Unlocks a vault. Throws [WrongPasswordException] or [CorruptedVaultException] (F-VAULT-2).
Future<({Object? data, SecretKey dek})> openVault(Envelope envelope, String password) async {
  final kek = await _deriveKek(password, base64Decode(envelope.salt), envelope.iterations);
  final SecretKey dek;
  try {
    dek = SecretKeyData(await _decrypt(kek, envelope.wrappedKey, _aadDek));
  } on SecretBoxAuthenticationError {
    throw const WrongPasswordException();
  }
  return (data: await _decryptJson(dek, envelope.payload, _aadPayload), dek: dek);
}

/// Decrypts a payload with an already-unlocked DEK (F-SYNC-4). Throws
/// [CorruptedVaultException] if the envelope belongs to another vault (F-SYNC-7).
Future<Object?> openPayload(Envelope envelope, SecretKey dek) => _decryptJson(dek, envelope.payload, _aadPayload);

/// Re-encrypts data with a fresh IV, keeping the KDF header and wrapped key.
Future<Envelope> sealVault(Envelope envelope, SecretKey dek, Object? data, [DateTime? now]) async {
  return envelope.copyWith({
    'payload': (await _encryptJson(dek, data, _aadPayload)).toJson(),
    'updatedAt': isoTimestamp(now ?? DateTime.now()),
  });
}

/// Re-wraps the same DEK under a new password; the payload is untouched (F-VAULT-5).
Future<Envelope> changePassword(Envelope envelope, SecretKey dek, String newPassword,
    {int iterations = defaultIterations, DateTime? now}) async {
  return envelope.copyWith({
    ...await _wrapDek(dek, newPassword, iterations),
    'updatedAt': isoTimestamp(now ?? DateTime.now()),
  });
}

/// Device-local data (the sync token) encrypted under the DEK; never synced (F-SYNC-8).
Future<CipherBlob> encryptLocalSecret(SecretKey dek, Object? value) => _encryptJson(dek, value, _aadLocalSecret);

Future<Object?> decryptLocalSecret(SecretKey dek, CipherBlob blob) => _decryptJson(dek, blob, _aadLocalSecret);

final _base64Re = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

bool _isBase64(Object? v) => v is String && v.isNotEmpty && v.length % 4 == 0 && _base64Re.hasMatch(v);

bool _isBlob(Object? v) => v is Map && _isBase64(v['iv']) && _isBase64(v['data']);

/// Validates untrusted JSON as an [Envelope] (vault-format §1).
Envelope parseEnvelope(Object? value) {
  if (value is! Map || value['format'] != vaultFormat) {
    throw const UnsupportedFormatException('不是 CipherPenny 账本文件');
  }
  if (value['version'] != vaultVersion) {
    throw UnsupportedFormatException('不支持的账本文件版本：${value['version']}');
  }
  final kdf = value['kdf'];
  final iterations = kdf is Map ? kdf['iterations'] : null;
  if (kdf is! Map ||
      kdf['name'] != 'PBKDF2' ||
      kdf['hash'] != 'SHA-256' ||
      iterations is! int ||
      iterations < minIterations ||
      iterations > _maxIterations ||
      !_isBase64(kdf['salt'])) {
    throw const UnsupportedFormatException('账本文件的密钥派生参数无效');
  }
  if (!_isBlob(value['wrappedKey']) || !_isBlob(value['payload']) || value['updatedAt'] is! String) {
    throw const UnsupportedFormatException('账本文件结构不完整');
  }
  return Envelope(value.cast<String, Object?>());
}
