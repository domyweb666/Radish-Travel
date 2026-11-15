// 對整趟做的事：收起來、先放一邊去排另一趟、切回來、變成一段可以傳給旅伴的文字。
// 都是直接改 draft 的純函式，由 store 的 act() 呼叫。
import { addDays, fmtDay } from './dates';
import { allItems, newId, planText } from './plan';
import type { AppState, BasketItem, Trip } from './types';

export const tripTitle = (t: Pick<Trip, 'days'>) => `首爾 ${t.days} 天`;

/** 這趟去過的站，照行程順序。收起來和做地圖網頁都用這一份 */
export function visitedOf(t: Trip): BasketItem[] {
  return allItems(t)
    .filter((x) => x.it.status === 'pulled')
    .map(({ it, s }) => ({ id: it.id, n: it.n, s: it.s, c: it.c, ic: it.ic, say: it.say, kr: it.kr || undefined, lat: it.lat, lng: it.lng, day: s.day, photos: it.photos }));
}

const bookingChecks = (checks: Record<string, boolean>) => Object.fromEntries(Object.entries(checks).filter(([k]) => k.startsWith('b_')));
const otherChecks = (checks: Record<string, boolean>) => Object.fromEntries(Object.entries(checks).filter(([k]) => !k.startsWith('b_')));

function clearCurrent(d: AppState, keepChecks = false) {
  d.trip = null;
  d.chat = [];
  d.debugDay = null;
  d.settingsDirty = false;
  if (!keepChecks) d.checks = otherChecks(d.checks);
}

/** 把這趟收起來：去過的站收進「去過的旅行」，行程清空 */
export function archiveTrip(d: AppState): string | undefined {
  if (!d.trip) return undefined;
  const items = visitedOf(d.trip);
  if (items.length) d.baskets.unshift({ id: newId('b'), title: `${tripTitle(d.trip)}・${fmtDay(d.trip.start)}出發`, items, start: d.trip.start, days: d.trip.days });
  // 收起來可以復原，所以勾選先不動；排下一趟時才清
  clearCurrent(d, true);
  return items.length ? `這趟去過的 ${items.length} 站收進「去過的旅行」了。` : '這趟收起來了。';
}

/** 現在這趟先放到「其他排好的」，讓出位置排新的一趟。什麼都不會不見 */
export function shelveCurrent(d: AppState): void {
  if (!d.trip) return;
  d.shelf.unshift({ id: newId('t'), trip: d.trip, chat: d.chat, checks: bookingChecks(d.checks), debugDay: d.debugDay });
  clearCurrent(d);
}

/** 切到另一趟：現在這趟先放一邊，再把那一趟拿出來 */
export function openShelved(d: AppState, id: string): string | undefined {
  const i = d.shelf.findIndex((x) => x.id === id);
  if (i < 0) return undefined;
  const [x] = d.shelf.splice(i, 1);
  shelveCurrent(d);
  d.trip = x.trip;
  d.chat = x.chat;
  d.debugDay = x.debugDay;
  d.checks = { ...d.checks, ...x.checks };
  return `切到「${tripTitle(x.trip)}・${fmtDay(x.trip.start)}出發」了。`;
}

export function shareText(trip: Trip): string {
  const end = addDays(trip.start, trip.days - 1);
  const body = planText(trip, false, (d) => fmtDay(addDays(trip.start, d - 1)));
  return `首爾 ${trip.days} 天　${fmtDay(trip.start)}–${fmtDay(end)}\n\n${body}\n（蘿蔔旅行排的。地點還沒核對過，看完跟我說哪天想改。）`;
}
