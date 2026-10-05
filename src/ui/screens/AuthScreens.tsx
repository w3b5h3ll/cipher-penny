import { useState, type FormEvent } from 'react';
import { CorruptedVaultError, session, WrongPasswordError } from '../../state/session';
import { errorMessage } from '../download';
import { Field } from '../components/controls';
import { ImportBackup } from './ImportBackup';

const MIN_PASSWORD_LENGTH = 8;

function Brand({ subtitle }: { subtitle: string }) {
  return (
    <div className="brand">
      <img src="./icon.svg" alt="" width={64} height={64} />
      <h1>CipherPenny</h1>
      <p className="muted">{subtitle}</p>
    </div>
  );
}

/** F-VAULT-1 */
export function SetupScreen() {
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [restoring, setRestoring] = useState(false);

  const tooShort = password.length > 0 && password.length < MIN_PASSWORD_LENGTH;
  const mismatch = confirm.length > 0 && password !== confirm;
  const canSubmit = password.length >= MIN_PASSWORD_LENGTH && password === confirm && acknowledged && !busy;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setBusy(true);
    setError(null);
    try {
      await session.create(password);
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <main className="auth">
      <Brand subtitle="端到端加密的个人记账本。数据只保存在这台设备的浏览器里。" />
      {restoring ? (
        <section className="card">
          <h2>从备份恢复</h2>
          <ImportBackup onCancel={() => setRestoring(false)} />
        </section>
      ) : (
        <form className="card" onSubmit={submit}>
          <h2>设置主密码</h2>
          <Field label="主密码" hint={tooShort ? `至少 ${MIN_PASSWORD_LENGTH} 位，建议使用一句容易记住的长口令` : undefined}>
            <input
              type="password"
              autoComplete="new-password"
              autoFocus
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </Field>
          <Field label="确认主密码" hint={mismatch ? '两次输入不一致' : undefined}>
            <input
              type="password"
              autoComplete="new-password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
          </Field>
          <label className="checkbox">
            <input type="checkbox" checked={acknowledged} onChange={(e) => setAcknowledged(e.target.checked)} />
            <span>我已了解：主密码只保存在我的脑子里，<strong>忘记后数据无法恢复</strong>，我会定期导出加密备份。</span>
          </label>
          {error ? <p className="error">{error}</p> : null}
          <button type="submit" className="primary block" disabled={!canSubmit}>
            {busy ? '正在生成密钥…' : '创建加密账本'}
          </button>
          <button type="button" className="link block" onClick={() => setRestoring(true)}>
            已有备份文件？从备份恢复
          </button>
        </form>
      )}
    </main>
  );
}

/** F-VAULT-2 */
export function UnlockScreen() {
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showForgot, setShowForgot] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!password || busy) return;
    setBusy(true);
    setError(null);
    try {
      await session.unlock(password);
    } catch (err) {
      setPassword('');
      if (err instanceof WrongPasswordError) setError('密码错误');
      else if (err instanceof CorruptedVaultError) setError('本地数据已损坏或被篡改，无法解密');
      else setError(errorMessage(err));
      setBusy(false);
    }
  }

  async function wipe() {
    if (!window.confirm('确定清空这台设备上的全部账本数据吗？此操作无法撤销。')) return;
    if (!window.confirm('再次确认：没有备份的数据将永久丢失。')) return;
    await session.wipe();
  }

  return (
    <main className="auth">
      <Brand subtitle="账本已锁定" />
      <form className="card" onSubmit={submit}>
        <Field label="主密码">
          <input
            type="password"
            autoComplete="current-password"
            autoFocus
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </Field>
        {error ? <p className="error">{error}</p> : null}
        <button type="submit" className="primary block" disabled={!password || busy}>
          {busy ? '正在解锁…' : '解锁'}
        </button>
        <button type="button" className="link block" onClick={() => setShowForgot((v) => !v)}>
          忘记密码？
        </button>
        {showForgot ? (
          <div className="notice">
            <p>主密码无法找回，这是端到端加密的代价。你可以清空本地数据重新开始，再用以前导出的备份（需要备份当时的密码）恢复。</p>
            <button type="button" className="danger" onClick={() => void wipe()}>
              清空本地数据
            </button>
          </div>
        ) : null}
      </form>
    </main>
  );
}
