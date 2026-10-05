import { useState, type ChangeEvent, type FormEvent } from 'react';
import {
  CorruptedVaultError,
  parseEnvelope,
  session,
  WrongPasswordError,
  type Envelope,
} from '../../state/session';
import { errorMessage } from '../download';
import { Field } from '../components/controls';

/** F-IO-2: pick a backup file, enter its password, replace local data. */
export function ImportBackup({ onCancel, onDone, replacing }: { onCancel?: () => void; onDone?: () => void; replacing?: boolean }) {
  const [backup, setBackup] = useState<Envelope | null>(null);
  const [fileName, setFileName] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onFile(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    setError(null);
    setBackup(null);
    if (!file) return;
    setFileName(file.name);
    try {
      setBackup(parseEnvelope(JSON.parse(await file.text()) as unknown));
    } catch (err) {
      setError(err instanceof SyntaxError ? '文件不是有效的 JSON' : errorMessage(err));
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!backup || !password || busy) return;
    if (replacing && !window.confirm('导入后将用备份替换当前设备上的全部数据，主密码也会变成备份的密码。确定继续？')) return;
    setBusy(true);
    setError(null);
    try {
      await session.importBackup(backup, password);
      onDone?.();
    } catch (err) {
      if (err instanceof WrongPasswordError) setError('备份密码错误');
      else if (err instanceof CorruptedVaultError) setError('备份文件已损坏');
      else setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="stack">
      <Field label="备份文件（.cpenny.json）">
        <input type="file" accept=".json,application/json" onChange={(e) => void onFile(e)} />
      </Field>
      {backup ? (
        <>
          <p className="muted small">
            {fileName} · 备份时间 {new Date(backup.updatedAt).toLocaleString('zh-CN')}
          </p>
          <Field label="备份的主密码">
            <input type="password" autoComplete="off" value={password} onChange={(e) => setPassword(e.target.value)} />
          </Field>
        </>
      ) : null}
      {error ? <p className="error">{error}</p> : null}
      <div className="row">
        <button type="submit" className="primary" disabled={!backup || !password || busy}>
          {busy ? '正在解密…' : '恢复'}
        </button>
        {onCancel ? (
          <button type="button" onClick={onCancel}>
            取消
          </button>
        ) : null}
      </div>
    </form>
  );
}
