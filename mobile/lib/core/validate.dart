import 'model.dart';

class InvalidVaultDataException implements Exception {
  const InvalidVaultDataException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Structural check of decrypted data before it is used (port of src/core/validate.ts).
VaultData assertVaultData(Object? value) {
  if (value is! Map) throw const InvalidVaultDataException('账本数据格式无效');
  final v = value.cast<String, Object?>();
  if (v['schemaVersion'] != 1) throw InvalidVaultDataException('不支持的账本数据版本：${v['schemaVersion']}');
  for (final key in ['accounts', 'categories', 'transactions', 'recurring']) {
    if (v[key] is! List) throw InvalidVaultDataException('账本数据缺少字段：$key');
  }
  if (v['settings'] is! Map) throw const InvalidVaultDataException('账本数据缺少字段：settings');
  final deletions = v['deletions'];
  if (deletions != null &&
      !(deletions is List && deletions.every((d) => d is Map && d['id'] is String && d['deletedAt'] is String))) {
    throw const InvalidVaultDataException('账本数据字段无效：deletions');
  }
  return VaultData(v);
}
