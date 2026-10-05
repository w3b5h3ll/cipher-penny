import { useMemo, useSyncExternalStore } from 'react';
import type { Account, Category, VaultData } from '../core/model';
import { session, type SessionState } from '../state/session';

export function useSession(): SessionState {
  return useSyncExternalStore(session.subscribe, session.getState);
}

/** Only call below the unlocked gate in App. */
export function useVault(): VaultData {
  const state = useSession();
  if (state.status !== 'unlocked') throw new Error('useVault() used while locked');
  return state.data;
}

export interface Lookups {
  category: (id: string) => Category | undefined;
  account: (id: string) => Account | undefined;
  activeCategories: Category[];
  activeAccounts: Account[];
}

export function useLookups(data: VaultData): Lookups {
  return useMemo(() => {
    const categories = new Map(data.categories.map((c) => [c.id, c]));
    const accounts = new Map(data.accounts.map((a) => [a.id, a]));
    return {
      category: (id) => categories.get(id),
      account: (id) => accounts.get(id),
      activeCategories: data.categories.filter((c) => !c.archived),
      activeAccounts: data.accounts.filter((a) => !a.archived),
    };
  }, [data.categories, data.accounts]);
}
