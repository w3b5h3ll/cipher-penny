import type { Cents } from './model';

const MAX_CENTS = 1e12;

/** Parses user input like "35", "35.5", "1,234.56", "¥20" into cents. Returns null if invalid. */
export function parseAmount(input: string): Cents | null {
  const s = input.trim().replace(/[,，\s]/g, '').replace(/^[¥￥]/, '');
  const m = /^(\d+)(?:\.(\d{0,2}))?$/.exec(s);
  if (!m) return null;
  const yuan = Number(m[1]);
  const fen = Number((m[2] ?? '').padEnd(2, '0'));
  const cents = yuan * 100 + fen;
  if (!Number.isSafeInteger(cents) || cents > MAX_CENTS) return null;
  return cents;
}

/** 123456 -> "1,234.56" */
export function formatCents(cents: Cents): string {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(Math.round(cents));
  const yuan = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const fen = (abs % 100).toString().padStart(2, '0');
  return `${sign}${yuan}.${fen}`;
}

/** 123456 -> "¥1,234.56" */
export function formatMoney(cents: Cents): string {
  return cents < 0 ? `-¥${formatCents(-cents)}` : `¥${formatCents(cents)}`;
}

/** Value suitable for an <input>: 3500 -> "35", 3550 -> "35.50". */
export function centsToInput(cents: Cents): string {
  const yuan = Math.floor(cents / 100);
  const fen = cents % 100;
  return fen === 0 ? String(yuan) : `${yuan}.${fen.toString().padStart(2, '0')}`;
}
