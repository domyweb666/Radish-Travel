// 排行程的本機規則，從原型第三版搬過來。純函式，不碰畫面，tests/ 可以直接跑。
// 接上 AI 之後，第一版行程改由後端產生，這裡留著當離線與測試用的底。
import { ADJ, AREA, CAT, FLV, FOOD, HOTEL, PART, PLACES, PURPOSE, STAY } from '../data/seoul';
import type { AreaKey, Cat, FoodKind, Part, Place, Purpose, Seed, Settings, Slot, Stop, Trip, TripDraft } from './types';

export const PARTS: Part[] = ['am', 'pm', 'eve'];
const FOOD_KINDS: FoodKind[] = ['street', 'local', 'famous', 'fine'];
const CATS = Object.keys(CAT) as Cat[];

export const defaultSettings = (): Settings => ({
  stay: 'cheap',
  base: 'C',
  food: { street: 2, local: 3, famous: 1, fine: 0 },
  avoid: [],
  queue: 'some',
  mealMax: 1500,
  budget: 1500,
  play: { eat: 2 },
  purposes: [],
  tags: [],
  wish: '',
  pace: 'mid',
  wake: 'normal',
  move: 'transit',
  tuned: false,
});

export const money = (n: number) => 'NT$ ' + Math.round(n).toLocaleString('en-US');

export function foodLv(st: Settings): Record<FoodKind, number> {
  const any = FOOD_KINDS.some((k) => st.food[k] > 0);
  return any ? st.food : { street: 0, local: 1, famous: 0, fine: 0 };
}
export function foodPct(st: Settings): Record<FoodKind, number> {
  const f = foodLv(st);
  const t = FOOD_KINDS.reduce((a, k) => a + f[k], 0);
  return Object.fromEntries(FOOD_KINDS.map((k) => [k, Math.round((f[k] / t) * 100)])) as Record<FoodKind, number>;
}

function weights(st: Settings): Record<Cat, number> {
  const w = Object.fromEntries(CATS.map((k) => [k, 1 + 2 * (st.play[k] ?? 0)])) as Record<Cat, number>;
  for (const purpose of st.purposes) {
    if (purpose === 'rest') {
      w.nature += 2;
      w.cafe += 1;
    } else if (purpose === 'eat') w.eat += 2;
    else if (purpose === 'fun') w.fun += 2;
    else if (purpose === 'see') {
      w.sight += 2;
      w.art += 1;
    }
  }
  return w;
}

const PURPOSE_CATS: Record<Purpose, Cat[]> = {
  rest: ['nature', 'cafe'],
  eat: ['eat'],
  fun: ['fun'],
  see: ['sight', 'art'],
};

/** 這一站為什麼被排進來：先講使用者自己說過的，沒有才講位置 */
function prefWhy(p: Place, st: Settings): string {
  if (st.play[p.c] === 2) return `你最愛${CAT[p.c]}`;
  if (st.play[p.c] === 1) return `你喜歡${CAT[p.c]}`;
  const hit = st.purposes.find((purpose) => PURPOSE_CATS[purpose].includes(p.c) || (purpose === 'rest' && p.l));
  if (hit) return `你旅行想${PURPOSE[hit]}`;
  return p.s === 'L' ? `${AREA[p.a]}這一帶的主要景點` : `${AREA[p.a]}這一帶順路的小地方`;
}

const toStop = (p: Place, why: string): Stop => ({ ...p, status: 'kept', swaps: 0, why });

export function generate(d: TripDraft, st: Settings, shuffle = false, rnd: () => number = Math.random): Trip {
  const w = weights(st);
  const used = new Set<string>();
  const { pace } = st;
  const base = d.base ?? st.base;
  const rest = st.purposes.includes('rest');
  const lv = foodLv(st);
  const jit = () => (shuffle ? rnd() * 2.5 : 0);
  const score = (p: Place) => w[p.c] + (rest && p.l ? 2 : 0);
  const take = (areas: AreaKey[], size: 'L' | 'S' | null, want: ((p: Place) => boolean) | null, why: (p: Place) => string): Stop | null => {
    const c = PLACES.filter((p) => !used.has(p.id) && areas.includes(p.a) && (!size || p.s === size) && (!want || want(p)))
      .map((p) => [p, score(p) + jit()] as const)
      .sort((x, y) => y[1] - x[1]);
    if (!c.length) return null;
    used.add(c[0][0].id);
    return toStop(c[0][0], why(c[0][0]));
  };
  const near = (a: AreaKey): AreaKey[] => [a, ...ADJ[a]];
  const ALL = Object.keys(AREA) as AreaKey[];
  const areaScore = (a: AreaKey) => {
    const ps = PLACES.filter((p) => p.a === a);
    return ps.reduce((s, p) => s + score(p), 0) / ps.length + jit();
  };
  const order: AreaKey[] = ALL.filter((a) => a !== 'J')
    .map((a) => [a, areaScore(a)] as const)
    .sort((x, y) => y[1] - x[1])
    .map((x) => x[0]);
  const usedArea = new Set<AreaKey>();
  const slots: Slot[] = [];
  const nextArea = (): AreaKey => {
    const a = order.find((x) => !usedArea.has(x));
    if (a) {
      usedArea.add(a);
      return a;
    }
    usedArea.clear();
    usedArea.add(order[0]);
    return order[0];
  };
  const full: number[] = [];
  for (let i = 2; i < d.days; i++) full.push(i);
  const tripDays = new Set<number>();
  if (d.days >= 5 && pace !== 'slow' && (w.sight >= 3 || w.fun >= 3 || w.nature >= 3)) {
    for (let i = Math.min(2, full.length - 1); i < full.length && tripDays.size < 3; i += 4) tripDays.add(full[i]);
  }
  const dayOK = (p: Place) => p.c !== 'night' && (p.c !== 'eat' || ((p.f === 'street' || p.f === 'local') && lv[p.f] > 0));
  const pref = (p: Place) => prefWhy(p, st);
  // 晚餐照吃的比例分
  const tot = FOOD_KINDS.reduce((a, k) => a + lv[k], 0);
  const cnt: Record<FoodKind, number> = { street: 0, local: 0, famous: 0, fine: 0 };
  let eveK = 0;
  const nextKind = (): FoodKind => {
    eveK++;
    let best: FoodKind = 'local';
    let bv = -1e9;
    FOOD_KINDS.forEach((k) => {
      if (!lv[k]) return;
      const v = (lv[k] / tot) * eveK - cnt[k];
      if (v > bv) {
        bv = v;
        best = k;
      }
    });
    cnt[best]++;
    return best;
  };
  const dinnerWhy = (p: Place) => (p.f ? `晚餐排${FOOD[p.f].name}，你設的是「${FLV[lv[p.f]]}」` : pref(p));

  for (let day = 1; day <= d.days; day++) {
    let parts: Part[] = ['am', 'pm', 'eve'];
    if (day === 1) parts = ({ am: ['pm', 'eve'], pm: ['eve'], eve: [] } as Record<Part, Part[]>)[d.arrive];
    if (day === d.days) parts = ({ am: [], pm: ['am'], eve: ['am', 'pm'] } as Record<Part, Part[]>)[d.leave];
    if (d.days === 1) parts = parts.filter((p) => ({ am: ['pm', 'eve'], pm: ['eve'], eve: [] } as Record<Part, Part[]>)[d.arrive].includes(p));
    const edge = day === 1 || day === d.days;
    const fi = full.indexOf(day);
    const lightDay = !edge && (pace === 'fast' ? fi % 6 === 5 : fi % 3 === 2);
    let amA: AreaKey;
    let pmA: AreaKey;
    if (edge) amA = pmA = base;
    else if (tripDays.has(day)) amA = pmA = 'J';
    else {
      amA = nextArea();
      pmA = amA;
      if (pace !== 'slow') {
        pmA = ADJ[amA].filter((x) => !usedArea.has(x)).sort((x, y) => order.indexOf(x) - order.indexOf(y))[0] ?? amA;
        usedArea.add(pmA);
      }
    }
    const edgeWhy = () => (day === 1 ? '第一天剛到，排輕鬆的' : '最後一天要走，排輕鬆的');
    PARTS.forEach((part) => {
      if (!parts.includes(part)) {
        slots.push({ day, part, off: true, rest: false, items: [] });
        return;
      }
      const a = part === 'am' ? amA : pmA;
      const items: Stop[] = [];
      let rest = false;
      const add = (x: Stop | null) => {
        if (x) items.push(x);
      };
      const city: AreaKey[] = a === 'J' ? [base] : near(a);
      if (part === 'eve') {
        const k = nextKind();
        add(
          take(city, 'S', (p) => p.c === 'eat' && p.f === k, dinnerWhy) ??
            take(ALL, 'S', (p) => p.c === 'eat' && p.f === k, dinnerWhy) ??
            take(city, 'S', (p) => p.c === 'eat' && !!p.f && lv[p.f] > 0, dinnerWhy) ??
            take(ALL, 'S', (p) => p.c === 'eat' && !!p.f && lv[p.f] > 0, dinnerWhy),
        );
        if (pace === 'fast' && !edge) add(take(city, 'S', (p) => p.c !== 'eat' && !p.l, () => '節奏選「趕」，晚上多排一站'));
        if (pace !== 'slow') rest = true;
      } else if (edge) {
        add(
          take(near(a), 'S', (p) => dayOK(p) && (!!p.l || p.c === 'shop' || p.c === 'cafe' || p.c === 'eat'), edgeWhy) ??
            take(near(a), 'S', (p) => dayOK(p) && !p.b, edgeWhy),
        );
      } else if (a === 'J') {
        if (part === 'am') add(take(['J'], 'L', null, (p) => `${pref(p)}；近郊來回要一整個白天，排在行程中段`));
        else rest = true;
      } else {
        const big = !lightDay && (part === 'am' ? st.wake !== 'late' : pace !== 'slow' || st.wake === 'late');
        add((big ? take([a], 'L', null, pref) : null) ?? take([a], 'S', dayOK, pref) ?? take(near(a), 'S', dayOK, pref));
        if (pace === 'fast' || ((!items[0] || items[0].s === 'S') && pace !== 'slow')) {
          const first = items[0];
          const sameArea = () => (first ? `跟「${first.n}」同一帶，順路` : '這一帶順路的小站');
          add(take([a], 'S', dayOK, sameArea) ?? take(near(a), 'S', dayOK, sameArea));
        }
        if (pace === 'slow' && part === 'pm') rest = true;
      }
      if (!items.length) rest = true;
      slots.push({ day, part, items, rest });
    });
  }
  return { ...d, slots, flight: 0 };
}

/* ---------- 查詢 ---------- */
export const allItems = (t: Trip) => t.slots.flatMap((s) => s.items.map((it) => ({ it, s })));
export const usedIds = (t: Trip) => new Set(allItems(t).map((x) => x.it.id));
export const halfDays = (t: Trip) => t.slots.filter((s) => !s.off && s.part !== 'eve').length;
export const findItem = (t: Trip, id: string) => allItems(t).find((x) => x.it.id === id);
export const slotAt = (t: Trip, day: number, part: Part) => t.slots.find((s) => s.day === day && s.part === part && !s.off);
export const bigCount = (t: Trip, day: number) => t.slots.filter((s) => s.day === day).flatMap((s) => s.items).filter((i) => i.s === 'L').length;
export const areaOf = (it: Pick<Stop, 'a' | 'mine'>) => (it.a ? AREA[it.a] : it.mine ? '自己加的' : 'AI 加的');
export const dayStops = (t: Trip, day: number) => t.slots.filter((s) => s.day === day && !s.off).flatMap((s) => s.items.map((it) => ({ it, s })));

export function warnings(t: Trip): string[] {
  const w: string[] = [];
  for (let d = 1; d <= t.days; d++) {
    const n = bigCount(t, d);
    if (n > 2) w.push(`第 ${d} 天現在有 ${n} 個大站，會很累。`);
  }
  return w;
}

/* ---------- 改行程（直接改傳進來的物件；呼叫端負責先複製） ---------- */
let seq = 0;
export const newId = (prefix: string) => `${prefix}${Date.now().toString(36)}${(seq++).toString(36)}`;

export function moveItem(t: Trip, id: string, day: number, part: Part): string | null {
  const x = findItem(t, id);
  const to = slotAt(t, day, part);
  if (!x) return '找不到那一站';
  if (!to) return `第 ${day} 天${PART[part] ?? ''}你在路上，放不進去`;
  if (to === x.s) return null;
  x.s.items = x.s.items.filter((i) => i !== x.it);
  if (!x.s.items.length) x.s.rest = true;
  to.items.push(x.it);
  if (part !== 'eve') to.rest = false;
  return null;
}

export function swapParts(t: Trip, day: number, a: Part, b: Part): string | null {
  const A = slotAt(t, day, a);
  const B = slotAt(t, day, b);
  if (!A || !B) return `第 ${day} 天沒有兩個時段可以對調`;
  [A.items, B.items] = [B.items, A.items];
  [A.rest, B.rest] = [B.rest, A.rest];
  return null;
}

export function swapDays(t: Trip, a: number, b: number): string | null {
  let moved = 0;
  PARTS.forEach((p) => {
    const A = slotAt(t, a, p);
    const B = slotAt(t, b, p);
    if (A && B) {
      [A.items, B.items] = [B.items, A.items];
      [A.rest, B.rest] = [B.rest, A.rest];
      moved++;
    }
  });
  return moved ? null : '這兩天沒有對得上的時段';
}

/** 拿掉一站，放進「下次再來」。整站留著，之後可以排回這趟 */
export function seedOut(t: Trip, seeds: Seed[], id: string, why: string): Stop | null {
  const x = findItem(t, id);
  if (!x) return null;
  seeds.unshift({ id: newId('s'), n: x.it.n, a: areaOf(x.it), why, stop: x.it, from: { day: x.s.day, part: x.s.part } });
  x.s.items = x.s.items.filter((i) => i !== x.it);
  if (!x.s.items.length) x.s.rest = true;
  return x.it;
}

/** 把「下次再來」的一站排回這趟：先放回原本的時段，不行就找最空的白天 */
export function restoreSeed(t: Trip, seeds: Seed[], seedId: string): string {
  const i = seeds.findIndex((s) => s.id === seedId);
  if (i < 0) return '找不到那一站';
  const seed = seeds[i];
  const stop: Stop =
    seed.stop ?? { id: newId('m'), n: seed.n, kr: '', a: '', s: 'S', c: 'sight', lat: null, lng: null, mine: true, status: 'kept', swaps: 0, why: '你從「下次再來」排回來的' };
  let to = seed.from ? slotAt(t, seed.from.day, seed.from.part) : undefined;
  if (!to) to = emptiestSlot(t);
  if (!to) return '這趟每個時段都在路上，排不進去';
  stop.status = 'kept';
  to.items.push(stop);
  if (to.part !== 'eve') to.rest = false;
  seeds.splice(i, 1);
  return `「${stop.n}」排回第 ${to.day} 天${PART[to.part]}了`;
}

function emptiestSlot(t: Trip): Slot | undefined {
  const day = t.slots.filter((s) => !s.off && s.part !== 'eve');
  const mid = day.filter((s) => s.day > 1 && s.day < t.days && bigCount(t, s.day) < 2);
  return (mid.length ? mid : day).sort((x, y) => x.items.length - y.items.length)[0] ?? t.slots.find((s) => !s.off);
}

export function addOwn(t: Trip, seeds: Seed[], name: string): string {
  const slot = emptiestSlot(t);
  const it: Stop = { id: newId('m'), n: name, kr: '', a: '', s: 'L', c: 'sight', lat: null, lng: null, mine: true, status: 'kept', swaps: 0, why: '你自己加的' };
  if (!slot) {
    seeds.unshift({ id: newId('s'), n: name, a: '自己加的', why: '這趟排不進去', stop: it });
    return `這趟排不進去，「${name}」先放到下次再來`;
  }
  slot.items.push(it);
  slot.rest = false;
  return `「${name}」排在第 ${slot.day} 天${PART[slot.part]}`;
}

/** 同一帶、同大小的三個替代選項 */
export function alternatives(t: Trip, st: Settings, it: Stop): Place[] {
  const used = usedIds(t);
  const w = weights(st);
  const ar: AreaKey[] = it.a ? [it.a, ...ADJ[it.a]] : (Object.keys(AREA) as AreaKey[]);
  return PLACES.filter((p) => !used.has(p.id) && ar.includes(p.a) && p.s === it.s && (it.c !== 'eat' || p.c === 'eat'))
    .sort((a, b) => w[b.c] - w[a.c])
    .slice(0, 3);
}

export function replaceWith(t: Trip, fromId: string, p: Place): string | null {
  const x = findItem(t, fromId);
  if (!x) return '找不到要換掉的那一站';
  x.s.items[x.s.items.indexOf(x.it)] = { ...toStop(p, `你把「${x.it.n}」換成這個`), swaps: x.it.swaps + 1 };
  return null;
}

/** 順路可去：當天去的那幾帶裡，還沒排進來的小站 */
export function nearbyPool(t: Trip, day: number): string[] {
  const used = usedIds(t);
  const areas = [...new Set(dayStops(t, day).map((x) => x.it.a).filter(Boolean))];
  return PLACES.filter((p) => areas.includes(p.a) && !used.has(p.id) && p.s === 'S')
    .slice(0, 3)
    .map((p) => p.n);
}

/* ---------- 怎麼去、多遠、多久（估算） ---------- */
type Pt = { lat: number | null; lng: number | null };
export interface Leg {
  mode: string;
  km: number;
  min: number;
  cost: number;
}

export function km(a: Pt, b: Pt): number | null {
  if (a.lat == null || b.lat == null || a.lng == null || b.lng == null) return null;
  const R = 6371;
  const r = (x: number) => (x * Math.PI) / 180;
  const dLa = r(b.lat - a.lat);
  const dLo = r(b.lng - a.lng);
  const h = Math.sin(dLa / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLo / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h)) * 1.3; // 直線距離加三成，當成實際要走的路
}

export function leg(a: Pt, b: Pt, st: Settings): Leg | null {
  const d = km(a, b);
  if (d == null) return null;
  const walkMax = st.move === 'walk' ? 2 : 1;
  if (d < 0.15) return { mode: '就在旁邊', km: d, min: 2, cost: 0 };
  if (d <= walkMax) return { mode: '走路', km: d, min: Math.round(d * 13), cost: 0 };
  if (d >= 25) return { mode: '火車或巴士', km: d, min: Math.round(d * 1.3 + 25), cost: 250 };
  if (st.move === 'taxi') return { mode: '計程車', km: d, min: Math.round(d * 2.4 + 6), cost: d * 30 + 110 };
  return { mode: '地鐵或公車', km: d, min: Math.round(d * 2.6 + 10), cost: 35 };
}

export const baseOf = (t: Pick<Trip, 'base'> | null | undefined, st: Settings) => t?.base ?? st.base;
export const hotelPt = (st: Settings, t?: Pick<Trip, 'base'> | null) => HOTEL[baseOf(t, st)];
/** 重排時要帶回去的那幾項 */
export const draftOf = (t: Trip): TripDraft => ({ city: t.city, base: t.base, stayName: t.stayName, start: t.start, days: t.days, arrive: t.arrive, leave: t.leave, people: t.people });

/** 這一天每一段：住的地方 → 第 1 站 → … → 住的地方。長度是站數＋1 */
export function dayLegs(t: Trip, st: Settings, day: number): Array<Leg | null> {
  const stops = dayStops(t, day).map((x) => x.it);
  if (!stops.length) return [];
  const pts: Pt[] = [hotelPt(st, t), ...stops, hotelPt(st, t)];
  return pts.slice(0, -1).map((p, i) => leg(p, pts[i + 1], st));
}

export const legText = (l: Leg | null) => (l ? `${l.mode}・約 ${l.km.toFixed(1)} 公里・${l.min} 分鐘（估）` : '這一段距離不明，到時候查地圖');

/* ---------- 花費（粗估） ---------- */
export interface CostRow {
  name: string;
  amount: number;
  note: string;
}
export function cost(t: Trip, st: Settings): { rows: CostRow[]; total: number; people: number } {
  const n = t.people || 1;
  const nights = Math.max(t.days - 1, 0);
  const items = allItems(t).map((x) => x.it);
  const perNight = STAY[st.stay].perNight;
  const stay = (nights * perNight) / (n >= 2 ? 2 : 1);
  const fineExtra = items.filter((i) => i.c === 'eat').reduce((s, i) => s + (i.fee ?? 0), 0);
  const food = t.days * st.budget + fineExtra;
  const ticket = items.filter((i) => i.c !== 'eat').reduce((s, i) => s + (i.fee ?? 0), 0);
  let move = 600;
  for (let d = 1; d <= t.days; d++) dayLegs(t, st, d).forEach((l) => l && (move += l.mode === '計程車' ? l.cost / n : l.cost));
  const rows: CostRow[] = [
    { name: '住宿', amount: stay, note: `${nights} 晚 × ${money(perNight)}${n >= 2 ? '，兩人分' : ''}` },
    { name: '吃喝', amount: food, note: `${t.days} 天 × ${money(st.budget)}${fineExtra ? '，名店另加 ' + money(fineExtra) : ''}` },
    { name: '門票與體驗', amount: ticket, note: '這趟要付費的站加總' },
    { name: '交通', amount: move, note: '市內移動＋機場來回' },
    { name: '行前', amount: 700, note: '網卡、旅遊險' },
    { name: '機票', amount: t.flight || 0, note: t.flight ? '你自己填的' : '還沒填' },
  ];
  return { rows, total: rows.reduce((s, r) => s + r.amount, 0), people: n };
}

/** 每人粗估，講成一個區間 */
export function costRange(t: Trip, st: Settings): string {
  const c = cost(t, st);
  return `${money(c.total * 0.85)}–${money(c.total * 1.15)}`;
}

/* ---------- 給人看的文字 ---------- */
export function settingsSummary(st: Settings): string {
  const fp = foodPct(st);
  const likes = CATS.filter((k) => st.play[k])
    .sort((a, b) => (st.play[b] ?? 0) - (st.play[a] ?? 0))
    .map((k) => CAT[k] + (st.play[k] === 2 ? '（最愛）' : ''));
  const food = FOOD_KINDS.filter((k) => fp[k])
    .map((k) => `${FOOD[k].name} ${fp[k]}%`)
    .join('、');
  const pace = { slow: '輕鬆', mid: '剛好', fast: '排滿' }[st.pace];
  const want = st.purposes.length ? '；旅行想' + st.purposes.map((k) => PURPOSE[k]).join('、') : '';
  const more = [...st.tags, st.wish].filter(Boolean).join('、');
  return `住${STAY[st.stay].name}、${HOTEL[st.base].n}一帶；吃的是${food}，一天吃喝 ${money(st.budget)}${st.avoid.length ? '，不吃' + st.avoid.join('、') : ''}；喜歡${likes.join('、') || '什麼都可以'}；節奏${pace}${want}${more ? '；還想：' + more : ''}`;
}

/** 整趟的純文字版，給 AI 看，也用來傳給旅伴 */
export function planText(t: Trip, withIds = false, fmtDate?: (day: number) => string): string {
  let s = '';
  for (let d = 1; d <= t.days; d++) {
    s += `第 ${d} 天${fmtDate ? ' ' + fmtDate(d) : ''}\n`;
    PARTS.forEach((p) => {
      const sl = t.slots.find((x) => x.day === d && x.part === p);
      if (!sl) return;
      if (sl.off) {
        s += `  ${PART[p]}：在路上\n`;
        return;
      }
      const items = sl.items.map((i) => (withIds ? `[${i.id}] ${i.n}(${i.s === 'L' ? '大' : '小'},${CAT[i.c]},${areaOf(i)})` : i.n + (i.b ? '（要先訂）' : '')));
      s += `  ${PART[p]}：${items.join('、') || (sl.rest ? '留白' : '空的')}${withIds && sl.rest ? '；留白' : ''}\n`;
    });
  }
  return s;
}
