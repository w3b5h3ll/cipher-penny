import { useState, type FormEvent } from 'react';
import { todayISO } from '../../core/dates';
import { toCSV } from '../../core/csv';
import { newId } from '../../core/id';
import { updateSettings, upsertAccount, upsertCategory } from '../../core/ledger';
import { ACCOUNT_KIND_LABEL, type Account, type AccountKind, type Category } from '../../core/model';
import { session, WrongPasswordError } from '../../state/session';
import { Field } from '../components/controls';
import { downloadText, errorMessage } from '../download';
import { useVault } from '../hooks';
import { ImportBackup } from './ImportBackup';

function AccountEditor({ account, onDone }: { account?: Account; onDone: () => void }) {
  const [name, setName] = useState(account?.name ?? '');
  const [kind, setKind] = useState<AccountKind>(account?.kind ?? 'ewallet');
  const valid = name.trim().length > 0;

  function save(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    session.update((d) =>
      upsertAccount(d, {
        ...account,
        id: account?.id ?? newId(),
        name: name.trim(),
        kind,
        initialBalance: account?.initialBalance ?? 0,
        archived: account?.archived ?? false,
      }),
    );
    onDone();
  }

  return (
    <form className="inline-editor" onSubmit={save}>
      <input value={name} onChange={(e) => setName(e.target.value)} placeholder="账户名称" aria-label="账户名称" autoFocus />
      <select value={kind} onChange={(e) => setKind(e.target.value as AccountKind)} aria-label="账户类型">
        {(Object.keys(ACCOUNT_KIND_LABEL) as AccountKind[]).map((k) => (
          <option key={k} value={k}>
            {ACCOUNT_KIND_LABEL[k]}
          </option>
        ))}
      </select>
      <button type="submit" className="primary" disabled={!valid}>
        保存
      </button>
      <button type="button" onClick={onDone}>
        取消
      </button>
    </form>
  );
}

function AccountsSection() {
  const data = useVault();
  const [editing, setEditing] = useState<string | null>(null);

  return (
    <section className="card stack">
      <div className="row between">
        <h2>账户</h2>
        <button type="button" onClick={() => setEditing('new')}>
          + 新增
        </button>
      </div>
      <ul className="plain-list">
        {data.accounts.map((a) =>
          editing === a.id ? (
            <li key={a.id}>
              <AccountEditor account={a} onDone={() => setEditing(null)} />
            </li>
          ) : (
            <li key={a.id} className={`row between ${a.archived ? 'archived' : ''}`}>
              <span>
                {a.name} <span className="muted small">{ACCOUNT_KIND_LABEL[a.kind]}</span>
                {a.archived ? <span className="badge">已归档</span> : null}
              </span>
              <span className="row">
                <button type="button" className="small-btn" onClick={() => setEditing(a.id)}>
                  编辑
                </button>
                <button
                  type="button"
                  className="small-btn"
                  onClick={() => session.update((d) => upsertAccount(d, { ...a, archived: !a.archived }))}
                >
                  {a.archived ? '恢复' : '归档'}
                </button>
              </span>
            </li>
          ),
        )}
        {editing === 'new' ? (
          <li>
            <AccountEditor onDone={() => setEditing(null)} />
          </li>
        ) : null}
      </ul>
      <p className="muted small">归档的账户不再出现在选择列表中，已有账单保留。</p>
    </section>
  );
}

function CategoryEditor({ category, onDone }: { category?: Category; onDone: () => void }) {
  const [icon, setIcon] = useState(category?.icon ?? '🏷️');
  const [name, setName] = useState(category?.name ?? '');
  const [keywords, setKeywords] = useState(category?.keywords.join('，') ?? '');
  const valid = name.trim().length > 0;

  function save(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    session.update((d) =>
      upsertCategory(d, {
        ...category,
        id: category?.id ?? newId(),
        name: name.trim(),
        type: category?.type ?? 'expense',
        icon: icon.trim() || '🏷️',
        keywords: keywords
          .split(/[,，、\s]+/)
          .map((k) => k.trim())
          .filter(Boolean),
        archived: category?.archived ?? false,
      }),
    );
    onDone();
  }

  return (
    <form className="inline-editor" onSubmit={save}>
      <input value={icon} onChange={(e) => setIcon(e.target.value)} className="emoji-input" aria-label="图标" />
      <input value={name} onChange={(e) => setName(e.target.value)} placeholder="分类名称" aria-label="分类名称" autoFocus />
      <input
        value={keywords}
        onChange={(e) => setKeywords(e.target.value)}
        placeholder="识别关键词，用逗号分隔"
        aria-label="关键词"
        className="grow"
      />
      <button type="submit" className="primary" disabled={!valid}>
        保存
      </button>
      <button type="button" onClick={onDone}>
        取消
      </button>
    </form>
  );
}

function CategoriesSection() {
  const data = useVault();
  const [editing, setEditing] = useState<string | null>(null);
  const list = data.categories.filter((c) => c.type === 'expense');

  return (
    <section className="card stack">
      <div className="row between">
        <h2>分类与识别关键词</h2>
        <button type="button" onClick={() => setEditing('new')}>
          + 新增
        </button>
      </div>
      <ul className="plain-list">
        {list.map((c) =>
          editing === c.id ? (
            <li key={c.id}>
              <CategoryEditor category={c} onDone={() => setEditing(null)} />
            </li>
          ) : (
            <li key={c.id} className={`row between ${c.archived ? 'archived' : ''}`}>
              <span className="category-line">
                <span>
                  {c.icon} {c.name}
                  {c.archived ? <span className="badge">已归档</span> : null}
                </span>
                <span className="muted small">{c.keywords.join('、') || '无关键词'}</span>
              </span>
              <span className="row">
                <button type="button" className="small-btn" onClick={() => setEditing(c.id)}>
                  编辑
                </button>
                <button
                  type="button"
                  className="small-btn"
                  onClick={() => session.update((d) => upsertCategory(d, { ...c, archived: !c.archived }))}
                >
                  {c.archived ? '恢复' : '归档'}
                </button>
              </span>
            </li>
          ),
        )}
        {editing === 'new' ? (
          <li>
            <CategoryEditor onDone={() => setEditing(null)} />
          </li>
        ) : null}
      </ul>
      <p className="muted small">快速记账时，文字里包含的关键词越长，匹配优先级越高。</p>
    </section>
  );
}

function SecuritySection() {
  const data = useVault();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const valid = current && next.length >= 8 && next === confirm && !busy;

  async function change(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    setMessage(null);
    try {
      await session.changePassword(current, next);
      setCurrent('');
      setNext('');
      setConfirm('');
      setMessage({ ok: true, text: '主密码已修改。之前导出的备份仍然使用旧密码。' });
    } catch (err) {
      setMessage({ ok: false, text: err instanceof WrongPasswordError ? '当前密码错误' : errorMessage(err) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card stack">
      <h2>安全</h2>
      <Field label="闲置自动锁定">
        <select
          value={data.settings.autoLockMinutes}
          onChange={(e) => session.update((d) => updateSettings(d, { autoLockMinutes: Number(e.target.value) }))}
        >
          {[1, 5, 15, 30, 60].map((m) => (
            <option key={m} value={m}>
              {m} 分钟
            </option>
          ))}
          <option value={0}>关闭</option>
        </select>
      </Field>
      <form className="stack" onSubmit={change}>
        <h3>修改主密码</h3>
        <div className="grid-3">
          <input type="password" autoComplete="current-password" placeholder="当前密码" value={current} onChange={(e) => setCurrent(e.target.value)} aria-label="当前密码" />
          <input type="password" autoComplete="new-password" placeholder="新密码（至少 8 位）" value={next} onChange={(e) => setNext(e.target.value)} aria-label="新密码" />
          <input type="password" autoComplete="new-password" placeholder="确认新密码" value={confirm} onChange={(e) => setConfirm(e.target.value)} aria-label="确认新密码" />
        </div>
        {message ? <p className={message.ok ? 'success small' : 'error small'}>{message.text}</p> : null}
        <div>
          <button type="submit" className="primary" disabled={!valid}>
            {busy ? '正在重新加密…' : '修改密码'}
          </button>
        </div>
      </form>
    </section>
  );
}

function BackupSection() {
  const data = useVault();
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function exportBackup() {
    setError(null);
    try {
      const envelope = await session.exportBackup();
      downloadText(`cipher-penny-${todayISO()}.cpenny.json`, JSON.stringify(envelope, null, 2), 'application/json');
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  function exportCSV() {
    if (!window.confirm('CSV 是明文文件，任何拿到它的人都能看到你的账单。确定导出？')) return;
    downloadText(`cipher-penny-${todayISO()}.csv`, toCSV(data), 'text/csv;charset=utf-8');
  }

  return (
    <section className="card stack">
      <h2>备份与导出</h2>
      <p className="muted small">加密备份需要主密码才能打开，可以放心保存到网盘。建议每月导出一次。</p>
      <div className="row wrap">
        <button type="button" className="primary" onClick={() => void exportBackup()}>
          导出加密备份
        </button>
        <button type="button" onClick={() => setImporting((v) => !v)}>
          从备份恢复
        </button>
        <button type="button" onClick={exportCSV}>
          导出 CSV（明文）
        </button>
      </div>
      {error ? <p className="error small">{error}</p> : null}
      {importing ? <ImportBackup replacing onCancel={() => setImporting(false)} onDone={() => setImporting(false)} /> : null}
    </section>
  );
}

function DangerSection() {
  async function wipe() {
    if (!window.confirm('确定清空这台设备上的全部账本数据吗？此操作无法撤销。')) return;
    if (!window.confirm('再次确认：如果没有导出备份，数据将永久丢失。')) return;
    await session.wipe();
  }

  return (
    <section className="card stack">
      <h2>隐私与数据</h2>
      <ul className="muted small bullets">
        <li>
          账本只以 <code>AES-256-GCM</code> 密文保存在本机浏览器（IndexedDB）中，密钥由主密码经{' '}
          <code>PBKDF2-SHA256</code> 派生，不会上传到任何服务器。
        </li>
        <li>
          快捷记账链接：在网址后加 <code>#/add?text=午饭25</code>，打开并解锁后直接显示识别结果，可做成桌面快捷方式。
        </li>
        <li>语音输入使用浏览器自带的语音识别服务，Chrome 会把音频发送到 Google 服务器进行识别。介意的话请改用键盘输入。</li>
        <li>清除浏览器网站数据会删除账本，请定期导出加密备份。</li>
      </ul>
      <div>
        <button type="button" className="danger" onClick={() => void wipe()}>
          清空本地数据
        </button>
      </div>
    </section>
  );
}

export function SettingsScreen() {
  return (
    <div className="stack">
      <AccountsSection />
      <CategoriesSection />
      <SecuritySection />
      <BackupSection />
      <DangerSection />
    </div>
  );
}
