import { useMemo, useSyncExternalStore } from 'react';

// Hash routing: GitHub Pages has no SPA fallback, so deep links must not hit the server.

export interface Route {
  path: string;
  query: URLSearchParams;
}

function subscribe(cb: () => void) {
  window.addEventListener('hashchange', cb);
  return () => window.removeEventListener('hashchange', cb);
}

export function useRoute(): Route {
  const hash = useSyncExternalStore(subscribe, () => window.location.hash);
  return useMemo(() => {
    const raw = hash.replace(/^#/, '') || '/';
    const [path = '/', qs = ''] = raw.split('?');
    return { path: path || '/', query: new URLSearchParams(qs) };
  }, [hash]);
}

export function navigate(to: string) {
  window.location.hash = to;
}

/** matchPath('/tx/:id', '/tx/abc') -> { id: 'abc' } */
export function matchPath(pattern: string, path: string): Record<string, string> | null {
  const p = pattern.split('/');
  const a = path.split('/');
  if (p.length !== a.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < p.length; i++) {
    const seg = p[i]!;
    if (seg.startsWith(':')) params[seg.slice(1)] = decodeURIComponent(a[i]!);
    else if (seg !== a[i]) return null;
  }
  return params;
}
