// 日期都用 'YYYY-MM-DD' 字串，算的時候一律用 UTC，避免時區把日期推前推後一天。
const WEEK = ['日', '一', '二', '三', '四', '五', '六'];
const DAY_MS = 86400000;

const toUTC = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
};
const fromUTC = (ms: number) => new Date(ms).toISOString().slice(0, 10);

export function todayISO(now: Date = new Date()): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`;
}

export const addDays = (iso: string, n: number) => fromUTC(toUTC(iso) + n * DAY_MS);
export const diffDays = (a: string, b: string) => Math.round((toUTC(b) - toUTC(a)) / DAY_MS);
export const weekday = (iso: string) => WEEK[new Date(toUTC(iso)).getUTCDay()];

/** 11/20（五） */
export function fmtDay(iso: string): string {
  const [, m, d] = iso.split('-').map(Number);
  return `${m}/${d}（${weekday(iso)}）`;
}

/** 這個月的格子：前面補空格，每格是 ISO 日期或 null */
export function monthGrid(year: number, month: number): Array<string | null> {
  const first = Date.UTC(year, month - 1, 1);
  const lead = new Date(first).getUTCDay();
  const days = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const cells: Array<string | null> = Array(lead).fill(null);
  for (let d = 1; d <= days; d++) cells.push(fromUTC(Date.UTC(year, month - 1, d)));
  while (cells.length % 7) cells.push(null);
  return cells;
}

export type Phase = { kind: 'plan'; daysToGo: number } | { kind: 'trip'; day: number } | { kind: 'done' };

/** 這趟現在在哪個階段：還沒出發、旅途中第幾天、已經回來 */
export function phaseOf(start: string, days: number, today: string, debugDay: number | null): Phase {
  if (debugDay != null) return debugDay > days ? { kind: 'done' } : { kind: 'trip', day: Math.max(1, debugDay) };
  const d = diffDays(start, today);
  if (d < 0) return { kind: 'plan', daysToGo: -d };
  if (d >= days) return { kind: 'done' };
  return { kind: 'trip', day: d + 1 };
}
