import { useState, type FormEvent } from 'react';
import { DEFAULT_SYNC_PATH, session, WrongPasswordError, type SyncSetup } from '../../state/session';
import { Field } from '../components/controls';
import { errorMessage } from '../download';
import { useSession } from '../hooks';

const TOKEN_URL = 'https://github.com/settings/personal-access-tokens/new';

function SyncHelp() {
  return (
    <ol className="muted small bullets">
      <li>
        在 GitHub 新建一个<strong>私有</strong>仓库专门放数据，例如 <code>cipher-penny-data</code>。不要用存放代码的公开仓库。
      </li>
      <li>
        打开{' '}
        <a href={TOKEN_URL} target="_blank" rel="noreferrer">
          创建 fine-grained 令牌
        </a>
        ：Repository access 选 <code>Only select repositories</code> 并只勾选这个仓库；Permissions 里把{' '}
        <code>Contents</code> 设为 <code>Read and write</code>。
      </li>
      <li>把生成的令牌粘贴到下面。令牌用你的数据密钥加密后只保存在这台设备上，不会进入同步文件和备份。</li>
    </ol>
  );
}

function SyncFields({ value, onChange }: { value: SyncSetup; onChange: (next: SyncSetup) => void }) {
  return (
    <>
      <Field label="仓库">
        <input
          value={value.repo}
          onChange={(e) => onChange({ ...value, repo: e.target.value })}
          placeholder="owner/cipher-penny-data"
          autoComplete="off"
          spellCheck={false}
        />
      </Field>
      <Field label="文件路径">
        <input
          value={value.path}
          onChange={(e) => onChange({ ...value, path: e.target.value })}
          placeholder={DEFAULT_SYNC_PATH}
          autoComplete="off"
          spellCheck={false}
        />
      </Field>
      <Field label="GitHub 令牌">
        <input
          type="password"
          value={value.token}
          onChange={(e) => onChange({ ...value, token: e.target.value })}
          placeholder="github_pat_…"
          autoComplete="off"
          spellCheck={false}
        />
      </Field>
    </>
  );
}

const emptySetup: SyncSetup = { repo: '', path: '', token: '' };

/** F-SYNC-1, F-SYNC-7, F-SYNC-8, F-SYNC-9 */
export function SyncSection() {
  const state = useSession();
  const [setup, setSetup] = useState<SyncSetup>(emptySetup);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (state.status !== 'unlocked') return null;
  const sync = state.sync;

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function connect(e: FormEvent) {
    e.preventDefault();
    if (!setup.repo || !setup.token || busy) return;
    await run(async () => {
      await session.connectSync(setup);
      setSetup(emptySetup);
    });
  }

  function disconnect() {
    if (!window.confirm('断开后这台设备不再同步，GitHub 上的文件会保留。确定断开？')) return;
    void run(() => session.disconnectSync());
  }

  function overwrite() {
    if (!window.confirm('GitHub 上的同步文件将被这台设备的数据替换，原文件只能从仓库的提交历史中找回。确定覆盖？')) return;
    void run(() => session.overwriteRemote());
  }

  if (!sync.configured) {
    return (
      <section className="card stack">
        <h2>同步</h2>
        <p className="muted small">
          把加密后的账本存到你自己的 GitHub 私有仓库，多台设备之间自动合并。GitHub 上只有密文，没有主密码无法读取。
        </p>
        <SyncHelp />
        <form className="stack" onSubmit={(e) => void connect(e)}>
          <SyncFields value={setup} onChange={setSetup} />
          {error ? <p className="error small">{error}</p> : null}
          <div>
            <button type="submit" className="primary" disabled={!setup.repo || !setup.token || busy}>
              {busy ? '正在检查仓库…' : '开启同步'}
            </button>
          </div>
        </form>
      </section>
    );
  }

  return (
    <section className="card stack">
      <h2>同步</h2>
      <p className="small">
        同步到 <code>{sync.repo}</code> 的 <code>{sync.path}</code>
      </p>
      <p className="muted small">
        {sync.syncing
          ? '正在同步…'
          : sync.lastSyncedAt
            ? `上次同步：${new Date(sync.lastSyncedAt).toLocaleString('zh-CN')}`
            : '尚未同步'}
      </p>
      {sync.error && !sync.foreign ? <p className="error small">同步失败：{sync.error}</p> : null}
      {sync.foreign ? (
        <div className="notice">
          <p className="error small">{sync.error}</p>
          <p className="small">
            如果仓库里的文件来自你以前创建的另一个账本，可以用这台设备的数据覆盖它；如果想改用仓库里的数据，请先导出备份，再清空本地数据，然后在首页选择“从 GitHub 恢复”。
          </p>
          <button type="button" className="danger" disabled={busy} onClick={overwrite}>
            用本机数据覆盖 GitHub 上的文件
          </button>
        </div>
      ) : null}
      {error ? <p className="error small">{error}</p> : null}
      <div className="row wrap">
        <button type="button" className="primary" disabled={busy || sync.syncing} onClick={() => void run(() => session.syncNow())}>
          立即同步
        </button>
        <button type="button" disabled={busy} onClick={disconnect}>
          断开同步
        </button>
      </div>
    </section>
  );
}

/** F-SYNC-6: set up a new device from the vault stored on GitHub. */
export function RestoreFromGitHub({ onCancel }: { onCancel: () => void }) {
  const [setup, setSetup] = useState<SyncSetup>(emptySetup);
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const canSubmit = Boolean(setup.repo && setup.token && password) && !busy;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setBusy(true);
    setError(null);
    try {
      await session.restoreFromRemote(setup, password);
    } catch (err) {
      setError(err instanceof WrongPasswordError ? '主密码错误' : errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <form className="stack" onSubmit={(e) => void submit(e)}>
      <p className="muted small">填写在其他设备上开启同步时使用的仓库，以及这台设备专用的令牌（也可以和其他设备共用一个）。</p>
      <SyncFields value={setup} onChange={setSetup} />
      <Field label="主密码">
        <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} />
      </Field>
      {error ? <p className="error">{error}</p> : null}
      <div className="row">
        <button type="submit" className="primary" disabled={!canSubmit}>
          {busy ? '正在下载并解密…' : '恢复'}
        </button>
        <button type="button" onClick={onCancel}>
          取消
        </button>
      </div>
    </form>
  );
}
