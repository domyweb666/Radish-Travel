// 實際花費：使用者一筆一筆記韓元，用自己填的匯率換成台幣。這裡只算，不碰畫面。
// 匯率是「1000 韓元換多少台幣」，app 不抓即時匯率，沒填就只顯示韓元。
import { newId } from './plan';
import type { Spend, Trip } from './types';

const KRW_MAX = 99999999;
const RATE_MAX = 100;

/** 重排行程時要留下來的：使用者自己填的機票、花費紀錄、匯率 */
export const ownOf = (t: Trip) => ({ flight: t.flight, spend: t.spend, rate: t.rate });

/** 使用者打的金額 → 韓元整數。打錯或空的是 0 */
export function parseKrw(text: string): number {
  const n = parseInt(text.replace(/\D/g, ''), 10) || 0;
  return Math.min(KRW_MAX, n);
}

/** 使用者打的匯率 → 數字。空的、0、不合理的都當成沒填 */
export function parseRate(text: string): number | undefined {
  const n = parseFloat(text.replace(/[^\d.]/g, ''));
  return n > 0 && n <= RATE_MAX ? n : undefined;
}

export const krwText = (n: number) => '₩ ' + Math.round(n).toLocaleString('en-US');

/** 換成台幣。沒填匯率就是 null，不猜 */
export const toTwd = (krw: number, rate: number | undefined): number | null => (rate ? Math.round((krw / 1000) * rate) : null);

export function spendTotal(t: Pick<Trip, 'spend' | 'rate'>): { count: number; krw: number; twd: number | null } {
  const list = t.spend ?? [];
  const krw = list.reduce((n, x) => n + x.krw, 0);
  return { count: list.length, krw, twd: toTwd(krw, t.rate) };
}

/** 記一筆，新的排最上面。金額是 0 就不記 */
export function addSpend(t: Trip, krw: number, note: string, day?: number): Spend | undefined {
  if (krw <= 0) return undefined;
  const x: Spend = { id: newId('s'), krw, note: note.trim() || undefined, day };
  t.spend = [x, ...(t.spend ?? [])];
  return x;
}

export function removeSpend(t: Trip, id: string): Spend | undefined {
  const x = t.spend?.find((y) => y.id === id);
  if (x) t.spend = t.spend?.filter((y) => y.id !== id);
  return x;
}
