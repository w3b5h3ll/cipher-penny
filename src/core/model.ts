/** Integer amount in fen (1/100 CNY). Always non-negative; direction comes from `TxType`. */
export type Cents = number;

/** Local calendar date, `YYYY-MM-DD`. */
export type ISODate = string;

export type TxType = 'expense' | 'income';

export type AccountKind = 'cash' | 'ewallet' | 'debit' | 'credit' | 'other';

export interface Account {
  id: string;
  name: string;
  kind: AccountKind;
  initialBalance: Cents;
  archived: boolean;
  /** ISO timestamp of the last edit; used by sync merge. Absent in pre-sync data. */
  updatedAt?: string;
}

export interface Category {
  id: string;
  name: string;
  type: TxType;
  icon: string;
  keywords: string[];
  archived: boolean;
  updatedAt?: string;
}

export interface Transaction {
  id: string;
  type: TxType;
  amount: Cents;
  categoryId: string;
  accountId: string;
  date: ISODate;
  note: string;
  createdAt: string;
  updatedAt: string;
  recurringId?: string;
}

export type TransactionInput = Omit<Transaction, 'id' | 'createdAt' | 'updatedAt'>;

export type Frequency = 'weekly' | 'monthly' | 'yearly';

export interface RecurringRule {
  id: string;
  name: string;
  type: TxType;
  amount: Cents;
  categoryId: string;
  accountId: string;
  note: string;
  frequency: Frequency;
  interval: number;
  startDate: ISODate;
  endDate?: ISODate;
  active: boolean;
  /** Last occurrence date for which a transaction has been generated. */
  lastGenerated?: ISODate;
  updatedAt?: string;
}

export interface Settings {
  /** Minutes of inactivity before auto-lock; 0 disables auto-lock. */
  autoLockMinutes: number;
  updatedAt?: string;
}

/** Tombstone left by a deletion so sync merge does not resurrect the record. */
export interface Deletion {
  id: string;
  deletedAt: string;
}

export interface VaultData {
  schemaVersion: 1;
  accounts: Account[];
  categories: Category[];
  transactions: Transaction[];
  recurring: RecurringRule[];
  settings: Settings;
  deletions?: Deletion[];
}

export const TX_TYPE_LABEL: Record<TxType, string> = {
  expense: '支出',
  income: '收入',
};

export const ACCOUNT_KIND_LABEL: Record<AccountKind, string> = {
  cash: '现金',
  ewallet: '电子钱包',
  debit: '储蓄卡',
  credit: '信用卡',
  other: '其他',
};

export const FREQUENCY_LABEL: Record<Frequency, string> = {
  weekly: '周',
  monthly: '月',
  yearly: '年',
};
