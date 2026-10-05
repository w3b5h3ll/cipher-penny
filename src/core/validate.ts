import type { VaultData } from './model';

/** Structural check of decrypted data before it is used. Unknown fields are preserved. */
export function assertVaultData(value: unknown): VaultData {
  if (typeof value !== 'object' || value === null) throw new Error('账本数据格式无效');
  const v = value as Record<string, unknown>;
  if (v.schemaVersion !== 1) throw new Error(`不支持的账本数据版本：${String(v.schemaVersion)}`);
  for (const key of ['accounts', 'categories', 'transactions', 'recurring'] as const) {
    if (!Array.isArray(v[key])) throw new Error(`账本数据缺少字段：${key}`);
  }
  if (typeof v.settings !== 'object' || v.settings === null) throw new Error('账本数据缺少字段：settings');
  if (
    v.deletions !== undefined &&
    !(
      Array.isArray(v.deletions) &&
      v.deletions.every(
        (d: unknown) =>
          typeof d === 'object' && d !== null && typeof (d as Record<string, unknown>).id === 'string' &&
          typeof (d as Record<string, unknown>).deletedAt === 'string',
      )
    )
  ) {
    throw new Error('账本数据字段无效：deletions');
  }
  return value as VaultData;
}
