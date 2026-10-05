import 'dart:convert';

import 'package:cipher_penny/crypto/vault_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';

const fast = minIterations;
final sample = {'schemaVersion': 1, 'note': '午饭 ¥35', 'list': [1, 2, 3]};

void main() {
  test('opens the web-generated test vector fixtures/vault-v1.json (N-PORT-1)', () async {
    final fixture = loadFixture('vault-v1.json');
    final envelope = parseEnvelope(fixture['envelope']);
    final opened = await openVault(envelope, fixture['password'] as String);
    expect(opened.data, fixture['data']);
    await expectLater(openVault(envelope, 'wrong'), throwsA(isA<WrongPasswordException>()));
  });

  test('round-trips, uses fresh IVs and never stores plaintext (F-VAULT-3)', () async {
    final created = await createVault('hunter2-long', sample, iterations: fast);
    expect(jsonEncode(created.envelope.raw), isNot(contains('午饭')));
    final resealed = await sealVault(created.envelope, created.dek, sample);
    expect(resealed.payload.iv, isNot(created.envelope.payload.iv));
    final opened = await openVault(parseEnvelope(jsonDecode(jsonEncode(resealed.raw))), 'hunter2-long');
    expect(opened.data, sample);
  });

  test('detects tampering of the payload', () async {
    final created = await createVault('hunter2-long', sample, iterations: fast);
    final bytes = base64Decode(created.envelope.payload.data);
    bytes[0] ^= 1;
    final tampered = created.envelope.copyWith({
      'payload': {'iv': created.envelope.payload.iv, 'data': base64Encode(bytes)},
    });
    await expectLater(openVault(tampered, 'hunter2-long'), throwsA(isA<CorruptedVaultException>()));
  });

  test('DEK-only helpers reject another vault and keep secrets separate (F-SYNC-7, F-SYNC-8)', () async {
    final a = await createVault('hunter2-long', sample, iterations: fast);
    final b = await createVault('hunter2-long', sample, iterations: fast);
    expect(await openPayload(a.envelope, a.dek), sample);
    await expectLater(openPayload(b.envelope, a.dek), throwsA(isA<CorruptedVaultException>()));
    final secret = await encryptLocalSecret(a.dek, {'token': 'github_pat_x'});
    expect(jsonEncode(secret.toJson()), isNot(contains('github_pat_x')));
    expect(await decryptLocalSecret(a.dek, secret), {'token': 'github_pat_x'});
    await expectLater(openPayload(a.envelope.copyWith({'payload': secret.toJson()}), a.dek),
        throwsA(isA<CorruptedVaultException>()));
  });

  test('parseEnvelope rejects malformed input', () {
    expect(() => parseEnvelope({'format': 'x'}), throwsA(isA<UnsupportedFormatException>()));
    expect(() => parseEnvelope({'format': vaultFormat, 'version': 2}), throwsA(isA<UnsupportedFormatException>()));
  });
}
