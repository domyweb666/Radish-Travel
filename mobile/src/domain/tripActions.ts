// 對整趟做的事：收起來、變成一段可以傳給旅伴的文字。
import { addDays, fmtDay } from './dates';
import { allItems, newId, planText } from './plan';
import type { AppState, Trip } from './types';

/** 把這趟收起來：拔過的站收進蘿蔔籃，行程清空。直接改 draft */
export function archiveTrip(d: AppState): string | undefined {
  if (!d.trip) return undefined;
  const items = allItems(d.trip)
    .filter((x) => x.it.status === 'pulled')
    .map(({ it }) => ({ n: it.n, s: it.s, c: it.c, ic: it.ic, say: it.say }));
  if (items.length) d.baskets.unshift({ id: newId('b'), title: `首爾 ${d.trip.days} 天・${fmtDay(d.trip.start)}出發`, items });
  d.trip = null;
  d.chat = [];
  d.debugDay = null;
  d.settingsDirty = false;
  return items.length ? `這一籃 ${items.length} 顆收進蘿蔔籃了。` : '這趟收起來了。';
}

export function shareText(trip: Trip): string {
  const end = addDays(trip.start, trip.days - 1);
  const body = planText(trip, false, (d) => fmtDay(addDays(trip.start, d - 1)));
  return `首爾 ${trip.days} 天　${fmtDay(trip.start)}–${fmtDay(end)}\n\n${body}\n（蘿蔔旅行排的。地點還沒核對過，看完跟我說哪天想改。）`;
}
