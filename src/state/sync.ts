import { mergeVaults } from '../core/merge';
import type { VaultData } from '../core/model';
import { assertVaultData } from '../core/validate';
import { openPayload, parseEnvelope, sealVault, type Envelope } from '../crypto/vault-crypto';
import { RemoteError, type RemoteFile } from '../remote/github';

// One sync round (F-SYNC-4, F-SYNC-5, F-SYNC-7). Normative rules: docs/vault-format.md §5.

export interface RemoteStore {
  read(): Promise<RemoteFile | null>;
  write(text: string, sha: string | null): Promise<string>;
}

/** What we knew after the last successful sync; persisted per device. */
export interface SyncCursor {
  /** Blob sha of the remote file right after the last sync. */
  remoteSha: string | null;
  /**
   * Payload IV of the local envelope right after the last sync. Every save uses a fresh
   * random IV, so a different value means local data changed (timestamps can collide).
   */
  localPayloadIv: string | null;
  /** The password was changed on this device since the last sync (vault-format §5.2). */
  keyChanged: boolean;
}

export type SyncResult =
  | { kind: 'unchanged'; remoteSha: string }
  | { kind: 'pushed'; remoteSha: string; envelope: Envelope }
  /** Remote had changes; the caller must adopt `envelope` and `data` locally. */
  | { kind: 'merged'; remoteSha: string; envelope: Envelope; data: VaultData };

export class ForeignVaultError extends Error {
  constructor() {
    super('远端文件无法用本机的密钥解密：它属于另一个账本，或者已损坏');
    this.name = 'ForeignVaultError';
  }
}

const MAX_ATTEMPTS = 3;

export function serializeEnvelope(envelope: Envelope): string {
  return `${JSON.stringify(envelope, null, 2)}\n`;
}

export async function syncOnce(input: {
  remote: RemoteStore;
  envelope: Envelope;
  data: VaultData;
  dek: CryptoKey;
  cursor: SyncCursor;
  now?: () => Date;
}): Promise<SyncResult> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await attemptSync(input);
    } catch (err) {
      const retry = err instanceof RemoteError && err.kind === 'conflict' && attempt < MAX_ATTEMPTS;
      if (!retry) throw err;
    }
  }
}

async function attemptSync({
  remote,
  envelope,
  data,
  dek,
  cursor,
  now = () => new Date(),
}: Parameters<typeof syncOnce>[0]): Promise<SyncResult> {
  const file = await remote.read();
  if (!file) {
    return { kind: 'pushed', remoteSha: await remote.write(serializeEnvelope(envelope), null), envelope };
  }

  if (file.sha === cursor.remoteSha) {
    if (envelope.payload.iv === cursor.localPayloadIv && !cursor.keyChanged) {
      return { kind: 'unchanged', remoteSha: file.sha };
    }
    return { kind: 'pushed', remoteSha: await remote.write(serializeEnvelope(envelope), file.sha), envelope };
  }

  const remoteEnvelope = await decodeRemote(file);
  const remoteData = await openRemote(remoteEnvelope, dek);
  const merged = mergeVaults(remoteData, data);
  if (!cursor.keyChanged && JSON.stringify(merged) === JSON.stringify(remoteData)) {
    return { kind: 'merged', remoteSha: file.sha, envelope: remoteEnvelope, data: remoteData };
  }
  const keys = cursor.keyChanged ? envelope : remoteEnvelope;
  const sealed = await sealVault(
    { ...envelope, kdf: keys.kdf, wrappedKey: keys.wrappedKey },
    dek,
    merged,
    now(),
  );
  const remoteSha = await remote.write(serializeEnvelope(sealed), file.sha);
  return { kind: 'merged', remoteSha, envelope: sealed, data: merged };
}

async function decodeRemote(file: RemoteFile): Promise<Envelope> {
  try {
    return parseEnvelope(JSON.parse(file.text));
  } catch {
    throw new ForeignVaultError();
  }
}

async function openRemote(envelope: Envelope, dek: CryptoKey): Promise<VaultData> {
  try {
    return assertVaultData(await openPayload(envelope, dek));
  } catch {
    throw new ForeignVaultError();
  }
}
