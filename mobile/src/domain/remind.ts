// 「要先訂的還沒訂」的提醒：哪一天提醒、提醒什麼。這裡只算，真的排通知在 io/reminders.ts。
import { addDays, fmtDay } from './dates';
import { allItems } from './plan';
import { tripTitle } from './tripActions';
import type { AppState, Stop, Trip } from './types';

const AHEAD = 7; // 出發前幾天提醒

/** 要先訂、還沒在「行前」打勾、也還沒去的站 */
export function unbookedOf(trip: Trip, checks: Record<string, boolean>): Stop[] {
  return allItems(trip)
    .filter((x) => x.it.b && x.it.status === 'kept' && !checks['b_' + x.it.id])
    .map((x) => x.it);
}

/** 哪一天提醒：出發前七天；已經不到七天就明天；明天就出發或已經出發就不提醒 */
export function remindOn(start: string, today: string): string | null {
  const early = addDays(start, -AHEAD);
  const on = early > today ? early : addDays(today, 1);
  return on < start ? on : null;
}

export interface Reminder {
  on: string;
  title: string;
  body: string;
}

/** 現在這趟和其他排好的，每一趟最多一則。沒有還沒訂的就沒有提醒 */
export function remindersOf(s: Pick<AppState, 'trip' | 'shelf' | 'checks'>, today: string): Reminder[] {
  const all: Array<{ trip: Trip; checks: Record<string, boolean> }> = [];
  if (s.trip) all.push({ trip: s.trip, checks: s.checks });
  s.shelf.forEach((x) => all.push({ trip: x.trip, checks: x.checks }));
  const out: Reminder[] = [];
  for (const { trip, checks } of all) {
    const left = unbookedOf(trip, checks);
    const on = remindOn(trip.start, today);
    if (!left.length || !on) continue;
    out.push({
      on,
      title: `${tripTitle(trip)}・${fmtDay(trip.start)}出發`,
      body: `有 ${left.length} 站要先訂，還沒打勾：${left.map((x) => x.n).join('、')}。`,
    });
  }
  return out;
}
