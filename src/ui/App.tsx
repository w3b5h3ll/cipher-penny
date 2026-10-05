import { useState } from 'react';
import { session, type SyncView } from '../state/session';
import { useSession } from './hooks';
import { matchPath, navigate, useRoute, type Route } from './router';
import { SetupScreen, UnlockScreen } from './screens/AuthScreens';
import { HomeScreen } from './screens/HomeScreen';
import { RecurringEditScreen, RecurringListScreen } from './screens/RecurringScreens';
import { SettingsScreen } from './screens/SettingsScreen';
import { StatsScreen } from './screens/StatsScreen';
import { TxEditScreen } from './screens/TxEditScreen';

const NAV = [
  { path: '/', label: '账单', match: (p: string) => p === '/' || p === '/add' || p.startsWith('/tx') },
  { path: '/stats', label: '统计', match: (p: string) => p === '/stats' },
  { path: '/recurring', label: '周期', match: (p: string) => p.startsWith('/recurring') },
  { path: '/settings', label: '设置', match: (p: string) => p === '/settings' },
];

function renderRoute({ path, query }: Route) {
  if (path === '/add') return <HomeScreen key={query.get('text') ?? ''} initialText={query.get('text') ?? undefined} />;
  if (path === '/tx/new') return <TxEditScreen key="new" />;
  const tx = matchPath('/tx/:id', path);
  if (tx) return <TxEditScreen key={tx.id} id={tx.id} />;
  if (path === '/stats') return <StatsScreen />;
  if (path === '/recurring') return <RecurringListScreen />;
  if (path === '/recurring/new') return <RecurringEditScreen key="new" />;
  const rec = matchPath('/recurring/:id', path);
  if (rec) return <RecurringEditScreen key={rec.id} id={rec.id} />;
  if (path === '/settings') return <SettingsScreen />;
  return <HomeScreen />;
}

function UnlockedShell({
  recurringCreated,
  saveError,
  sync,
}: {
  recurringCreated: number;
  saveError?: string;
  sync: SyncView;
}) {
  const route = useRoute();
  const [showRecurringNotice, setShowRecurringNotice] = useState(recurringCreated > 0);

  return (
    <>
      <header className="topbar">
        <button type="button" className="logo" onClick={() => navigate('/')}>
          <img src="./icon.svg" alt="" width={28} height={28} />
          <span>CipherPenny</span>
        </button>
        <nav>
          {NAV.map((n) => (
            <a key={n.path} href={`#${n.path}`} className={n.match(route.path) ? 'active' : ''}>
              {n.label}
            </a>
          ))}
        </nav>
        {sync.configured && sync.error ? (
          <button type="button" className="sync-alert" onClick={() => navigate('/settings')} title={sync.error}>
            同步失败
          </button>
        ) : null}
        <button type="button" className="icon-btn lock" onClick={() => void session.lock()} title="立即锁定" aria-label="立即锁定">
          🔒
        </button>
      </header>
      <main className="content">
        {saveError ? <p className="banner error">保存失败：{saveError}。请先导出备份，避免数据丢失。</p> : null}
        {showRecurringNotice ? (
          <p className="banner">
            已自动记入 {recurringCreated} 笔周期账单。
            <button type="button" className="link" onClick={() => setShowRecurringNotice(false)}>
              知道了
            </button>
          </p>
        ) : null}
        {renderRoute(route)}
      </main>
    </>
  );
}

export function App() {
  const state = useSession();
  switch (state.status) {
    case 'loading':
      return <main className="auth"><p className="muted">加载中…</p></main>;
    case 'error':
      return (
        <main className="auth">
          <p className="error">无法读取本地存储：{state.message}</p>
          <p className="muted small">请确认浏览器没有禁用网站数据（无痕模式下可能无法使用）。</p>
        </main>
      );
    case 'empty':
      return <SetupScreen />;
    case 'locked':
      return <UnlockScreen />;
    case 'unlocked':
      return <UnlockedShell recurringCreated={state.recurringCreated} saveError={state.saveError} sync={state.sync} />;
  }
}
