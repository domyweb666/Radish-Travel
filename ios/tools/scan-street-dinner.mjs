// 只吃路邊的人，晚上會不會空著：把 PlanGenerate.swift 排第一版行程的規則用 node 照搬，
// 讀真的資料包（seoul.json）和核對資料（seoul-checked.json），掃很多種出發日 × 天數 × 住哪一帶 × 節奏，
// 數有幾個「該有晚餐的晚上」一間吃的都沒排到。這台沒有 Swift 編譯器，所以靠這支看規則跑出來的結果。
//
// 跑法：node ios/tools/scan-street-dinner.mjs [出發日 YYYY-MM-DD，預設 2026-11-26，數字才比得起來] [掃幾天，預設 365]
//
// 照搬的規則（PlanGenerate.swift 的 generateBody，連同它用到的幫手）：
// - 偏好：defaultSettings()，吃的改成只有路邊（street 3，其他 0）；foodLv、planWeights、score、fits 照搬
// - 候選：mergePlaces（seoul.json 拿掉 drop、add 接在 after 後面），順序固定，同分取前面的（take 用 >）
// - 同一組一趟一間（placeGroup），晚餐全部挑不到才放寬同組第二間（sameGroupOK）
// - 休館：closedWhy（gone、off、closedOn 含農曆鍵、每月第幾個星期幾、每週固定休、國定假日的 shift）
// - 時段：partClosedWhy 只看「有沒有理由」：partsOn（星期、國定假日 h）蓋掉 parts，那天整天休就不算時段不開
// - 區域：areaScore 排序、nextArea 輪流、ADJ 鄰近、近郊日（tripDays）與 anyOpen
// - 一天的排法：第一天幾點到、最後一天幾點走、lightDay、白天 L 站與順路 S 站、少走、趕的晚上多一站、
//   白天最多一站吃的（dayOK：白天只排路邊和小館）、超過七天的白天放寬同組
// - 晚餐：nextKind 照比例分種類，city → ALL → 有在吃的 city → ALL → 同組第二間 city → ALL
// 簡化的：
// - 不洗牌（shuffle false，jit 是 0），跟 app 第一次排的一樣
// - 沒有 tweaks（帶長輩、輕鬆、想省、慶祝都沒開），身體限制、少走、以後都不排都是空的，所以天氣、樓梯、banned 那幾條不會擋
// - 說明文字（why）不組，只記排了哪一站
// - 到達固定上午、離開固定晚上（跟 DinnerTests 一樣），所以第一天有晚餐、最後一天晚上不算
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RES = join(dirname(fileURLToPath(import.meta.url)), '..', 'RadishCore', 'Sources', 'RadishCore', 'Resources');
const DATA = JSON.parse(readFileSync(join(RES, 'seoul.json'), 'utf8'));
const CK = JSON.parse(readFileSync(join(RES, 'seoul-checked.json'), 'utf8'));

const FOOD_KINDS = ['street', 'local', 'famous', 'fine'];
const CATS = ['eat', 'shop', 'fun', 'sight', 'art', 'nature', 'cafe', 'night', 'kpop'];
const PARTS = ['am', 'pm', 'eve'];
const AREAS = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'J']; // AreaKey.allCases 的順序
const ADJ = DATA.adj;

/* ---------- 候選地點（SeoulFacts.swift mergePlaces、placeGroup） ---------- */
const gone = new Set(CK.drop);
const PLACES = [];
for (const p of DATA.places) {
  if (!gone.has(p.id)) PLACES.push(p);
  for (const x of CK.add) if (x.after === p.id) PLACES.push(x.place);
}
const GROUP = new Map();
for (const p of PLACES) {
  let g = p.id;
  const hit = CK.add.find((x) => x.place.id === p.id);
  if (hit) g = gone.has(hit.after) ? hit.after : p.id;
  GROUP.set(p.id, g);
}
const placeGroup = (id) => GROUP.get(id) ?? id;

/* ---------- 日期（Dates.swift，UTC 算） ---------- */
const DAY = 86400000;
const toDays = (iso) => Math.round(Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) / DAY);
const fromDays = (n) => new Date(n * DAY).toISOString().slice(0, 10);
const addDays = (iso, n) => fromDays(toDays(iso) + n);
const dowOf = (iso) => new Date(toDays(iso) * DAY).getUTCDay();

/* ---------- 開不開（SeoulFacts.swift closedWhy、partClosedWhy） ---------- */
const HOL = new Set(CK.holidays);
function nthHit(f, iso) {
  const dow = dowOf(iso);
  const dom = +iso.slice(8, 10);
  const month = +iso.slice(5, 7);
  if (dom < 1) return null;
  const week = Math.floor((dom - 1) / 7) + 1;
  for (const n of f.closedNth ?? []) {
    if (n.dow !== dow || n.week !== week) continue;
    if (n.months && !n.months.includes(month)) continue;
    return n;
  }
  return null;
}
function closedWhy(f, iso) {
  if (f.gone) return f.gone;
  for (const o of f.off ?? []) {
    const before = iso < o.from;
    const after = o.to ? iso > o.to : false;
    if (!before && !after) return o.why;
  }
  for (const key of f.closedOn ?? []) {
    const days = CK.lunar[key];
    if (days) {
      if (days.includes(iso)) return '節日休';
    } else if (iso === key || iso.endsWith('-' + key)) return '節日休';
  }
  const dow = dowOf(iso);
  if (!HOL.has(iso) && nthHit(f, iso)) return 'nth';
  const weekly = f.closed ?? [];
  if (weekly.length === 0) return null;
  const holiday = f.shift != null && HOL.has(iso);
  if (weekly.includes(dow) && !holiday) return 'weekly';
  if (f.shift === 'next' && !holiday) {
    let d = addDays(iso, -1);
    let back = 0;
    while (back < 14 && HOL.has(d)) {
      if (weekly.includes(dowOf(d))) return 'shift';
      d = addDays(d, -1);
      back += 1;
    }
  }
  return null;
}
function openParts(f, iso) {
  if (HOL.has(iso) && f.partsOn?.h) return f.partsOn.h;
  const w = f.partsOn?.[String(dowOf(iso))];
  if (w) return w;
  return f.parts ?? null;
}
function partClosed(f, iso, part) {
  const parts = openParts(f, iso);
  if (!parts || parts.includes(part)) return false;
  return closedWhy(f, iso) == null;
}

/* ---------- 偏好（Plan.swift defaultSettings、foodLv、planWeights） ---------- */
function defaultSettings() {
  return {
    base: 'C', food: { street: 2, local: 3, famous: 1, fine: 0 }, walk: 'normal', body: [], learned: [],
    play: { eat: 2 }, purposes: [], pace: 'mid', wake: 'normal',
  };
}
function foodLv(st) {
  const f = {};
  let any = false;
  for (const k of FOOD_KINDS) {
    f[k] = st.food[k] ?? 0;
    if (f[k] > 0) any = true;
  }
  return any ? f : { street: 0, local: 1, famous: 0, fine: 0 };
}
function planWeights(st) {
  const w = {};
  for (const k of CATS) w[k] = 1 + 2 * (st.play[k] ?? 0);
  for (const p of st.purposes) {
    if (p === 'rest') { w.nature += 2; w.cafe += 1; }
    if (p === 'eat') w.eat += 2;
    if (p === 'fun') w.fun += 2;
    if (p === 'see') { w.sight += 2; w.art += 1; }
  }
  return w;
}
const stableSorted = (xs, less) =>
  xs.map((x, i) => [x, i]).sort((a, b) => (less(a[0], b[0]) ? -1 : less(b[0], a[0]) ? 1 : a[1] - b[1])).map((x) => x[0]);
const arriveParts = (a) => (a === 'am' ? ['pm', 'eve'] : a === 'pm' ? ['eve'] : []);
const leaveParts = (l) => (l === 'am' ? [] : l === 'pm' ? ['am'] : ['am', 'pm']);
const seasonOf = (start) => {
  const m = +start.slice(5, 7);
  if (m >= 6 && m <= 9) return 'hot';
  if (m === 12 || m <= 2) return 'cold';
  return null;
};
const outdoor = (p) => p.c === 'nature' || p.a === 'J';

/* ---------- 排一趟（PlanGenerate.swift generateBody，shuffle false） ---------- */
function generate(d, st) {
  const w = planWeights(st);
  const season = seasonOf(d.start);
  const weather = (season === 'hot' && st.body.includes('heat')) || (season === 'cold' && st.body.includes('cold'));
  const noUp = st.body.includes('stairs');
  const used = new Set();
  const pace = st.pace;
  const base = d.base ?? st.base;
  const wantRest = st.purposes.includes('rest');
  const lv = foodLv(st);
  const usedGroup = new Set();
  let sameGroupOK = false;
  let today = 1;
  let nowPart = 'am';
  let eatToday = 0;

  const score = (p) => {
    let v = w[p.c] ?? 0;
    if (wantRest && p.l === true) v += 2;
    if (st.walk === 'less' && p.l === true) v += 2;
    if (weather && outdoor(p)) v -= 3;
    return v;
  };
  const fits = (p) => !(noUp && p.up === true); // learned 是空的，banned 不會擋
  const shut = (p) => {
    const f = CK.facts[p.id];
    if (!f) return false;
    const iso = addDays(d.start, today - 1);
    if (closedWhy(f, iso) != null) return true;
    return partClosed(f, iso, nowPart);
  };
  const taken = (p) => used.has(p.id) || (!sameGroupOK && usedGroup.has(placeGroup(p.id)));
  const anyOpen = (a, size) => PLACES.some((p) => p.a === a && p.s === size && !taken(p) && fits(p) && !shut(p));
  const take = (areas, size, want) => {
    let best = null;
    let bestScore = 0;
    for (const p of PLACES) {
      if (!areas.includes(p.a)) continue;
      if (taken(p)) continue;
      if (!fits(p)) continue;
      if (size && p.s !== size) continue;
      if (want && !want(p)) continue;
      if (shut(p)) continue;
      const v = score(p);
      if (best == null || v > bestScore) { best = p; bestScore = v; }
    }
    if (!best) return null;
    used.add(best.id);
    usedGroup.add(placeGroup(best.id));
    if (best.c === 'eat' && nowPart !== 'eve') eatToday += 1;
    return best;
  };
  const near = (a) => [a, ...(ADJ[a] ?? [])];
  const areaScore = (a) => {
    let sum = 0;
    let count = 0;
    for (const p of PLACES) if (p.a === a && fits(p)) { sum += score(p); count += 1; }
    return count > 0 ? sum / count : 0;
  };
  const scored = AREAS.filter((a) => a !== 'J').map((a) => ({ a, v: areaScore(a) }));
  const order = stableSorted(scored, (x, y) => x.v > y.v).map((x) => x.a);
  const usedArea = new Set();
  const nextArea = () => {
    const free = order.find((x) => !usedArea.has(x));
    if (free) { usedArea.add(free); return free; }
    const first = order[0] ?? base;
    usedArea.clear();
    usedArea.add(first);
    return first;
  };
  const full = [];
  for (let i = 2; i < d.days; i++) full.push(i);
  const tripDays = new Set();
  if (d.days >= 5 && pace !== 'slow' && (w.sight >= 3 || w.fun >= 3 || w.nature >= 3)) {
    let i = Math.min(2, full.length - 1);
    while (i >= 0 && i < full.length && tripDays.size < 3) { tripDays.add(full[i]); i += 4; }
  }
  const dayOK = (p) => {
    if (p.c === 'night') return false;
    if (p.c !== 'eat') return true;
    if (eatToday > 0) return false;
    if (!p.f) return false;
    return (p.f === 'street' || p.f === 'local') && (lv[p.f] ?? 0) > 0;
  };
  let tot = 0;
  for (const k of FOOD_KINDS) tot += lv[k] ?? 0;
  const cnt = { street: 0, local: 0, famous: 0, fine: 0 };
  let eveK = 0;
  const nextKind = () => {
    eveK += 1;
    let best = 'local';
    let bv = -1e9;
    for (const k of FOOD_KINDS) {
      const level = lv[k] ?? 0;
      if (level === 0) continue;
      const v = (level / tot) * eveK - cnt[k];
      if (v > bv) { bv = v; best = k; }
    }
    cnt[best] += 1;
    return best;
  };
  const eatsNow = (p) => p.f != null && p.c === 'eat' && (lv[p.f] ?? 0) > 0;

  const slots = [];
  for (let day = 1; day <= d.days; day++) {
    today = day;
    nowPart = 'am';
    eatToday = 0;
    let parts = ['am', 'pm', 'eve'];
    if (day === 1) parts = arriveParts(d.arrive);
    if (day === d.days) parts = leaveParts(d.leave);
    if (d.days === 1) { const ok = arriveParts(d.arrive); parts = parts.filter((p) => ok.includes(p)); }
    const edge = day === 1 || day === d.days;
    const fi = full.indexOf(day);
    const lightDay = !edge && (pace === 'fast' ? fi % 6 === 5 : fi % 3 === 2);
    let amA = base;
    let pmA = base;
    if (edge) {
      amA = base; pmA = base;
    } else if (tripDays.has(day) && anyOpen('J', 'L')) {
      amA = 'J'; pmA = 'J';
    } else {
      amA = nextArea();
      pmA = amA;
      if (pace !== 'slow') {
        const free = (ADJ[amA] ?? []).filter((x) => !usedArea.has(x));
        const sorted = stableSorted(free, (x, y) => order.indexOf(x) < order.indexOf(y));
        pmA = sorted[0] ?? amA;
        usedArea.add(pmA);
      }
    }
    for (const part of PARTS) {
      if (!parts.includes(part)) { slots.push({ day, part, off: true, items: [] }); continue; }
      nowPart = part;
      const a = part === 'am' ? amA : pmA;
      const items = [];
      const city = a === 'J' ? [base] : near(a);
      if (part === 'eve') {
        const kind = nextKind();
        const isKind = (p) => p.c === 'eat' && p.f === kind;
        let dinner = take(city, 'S', isKind);
        if (!dinner) dinner = take(AREAS, 'S', isKind);
        if (!dinner) dinner = take(city, 'S', eatsNow);
        if (!dinner) dinner = take(AREAS, 'S', eatsNow);
        if (!dinner) {
          sameGroupOK = true;
          dinner = take(city, 'S', eatsNow);
          if (!dinner) dinner = take(AREAS, 'S', eatsNow);
          sameGroupOK = false;
        }
        if (dinner) items.push(dinner);
        if (pace === 'fast' && !edge) {
          const extra = take(city, 'S', (p) => p.c !== 'eat' && p.l !== true);
          if (extra) items.push(extra);
        }
      } else if (edge) {
        const easyOK = (p) => dayOK(p) && (p.l === true || p.c === 'shop' || p.c === 'cafe' || p.c === 'eat');
        const noBookOK = (p) => dayOK(p) && p.b !== true;
        let pick = take(near(a), 'S', easyOK);
        if (!pick) pick = take(near(a), 'S', noBookOK);
        if (pick) items.push(pick);
      } else if (a === 'J') {
        if (part === 'am') {
          const far = take(['J'], 'L', null);
          if (far) items.push(far);
        }
      } else {
        const bigTime = part === 'am' ? st.wake !== 'late' : pace !== 'slow' || st.wake === 'late';
        const big = !lightDay && bigTime;
        let pick = null;
        if (big) pick = take([a], 'L', null);
        if (!pick) pick = take([a], 'S', dayOK);
        if (!pick) pick = take(near(a), 'S', dayOK);
        if (pick) items.push(pick);
        const first = items[0] ?? null;
        const firstSmallOrNone = first ? first.s === 'S' : true;
        const lessAndHas = st.walk === 'less' && first != null;
        if (pace === 'fast' || (firstSmallOrNone && pace !== 'slow' && !lessAndHas)) {
          let more = take([a], 'S', dayOK);
          if (!more) more = take(near(a), 'S', dayOK);
          if (more) items.push(more);
        }
      }
      if (d.days > 7 && part !== 'eve' && a !== 'J' && items.length === 0) {
        const notEat = (p) => p.c !== 'eat' && dayOK(p);
        let fill = null;
        sameGroupOK = true;
        if (edge) {
          fill = take(near(a), 'S', (p) => notEat(p) && (p.l === true || p.c === 'shop' || p.c === 'cafe'));
          if (!fill) fill = take(near(a), 'S', (p) => notEat(p) && p.b !== true);
        } else {
          fill = take([a], 'S', notEat);
          if (!fill) fill = take(near(a), 'S', notEat);
        }
        sameGroupOK = false;
        if (fill) items.push(fill);
      }
      slots.push({ day, part, off: null, items });
    }
  }
  return slots;
}

/* ---------- 掃 ---------- */
const WEEK = ['日', '一', '二', '三', '四', '五', '六'];
const from = process.argv[2] ?? '2026-11-26';
const span = +(process.argv[3] ?? 365);
const BASES = Object.keys(DATA.hotel);
const PACES = ['slow', 'mid', 'fast'];
const street = PLACES.filter((p) => p.c === 'eat' && p.f === 'street');

console.log(`[scan-street-dinner] 路邊類 ${street.length} 間：${street.map((p) => `${p.n}（${p.a}）`).join('、')}`);
console.log(`[scan-street-dinner] 出發日 ${from} 起 ${span} 天 × 2 到 14 天 × 住 ${BASES.join('、')} × 節奏 ${PACES.join('、')}，上午到、晚上走`);

let trips = 0;
let nights = 0;
let empty = 0;
let tripsWithEmpty = 0;
const by = { base: {}, days: {}, pace: {}, dow: {}, nth: {} };
const bump = (o, k) => { o[k] = (o[k] ?? 0) + 1; };
const examples = [];
for (const pace of PACES) {
  const st = defaultSettings();
  st.pace = pace;
  st.food = { street: 3, local: 0, famous: 0, fine: 0 };
  for (let o = 0; o < span; o++) {
    const start = addDays(from, o);
    for (let days = 2; days <= 14; days++) {
      for (const base of BASES) {
        const slots = generate({ start, days, arrive: 'am', leave: 'eve', base }, st);
        trips += 1;
        let miss = 0;
        let nth = 0;
        for (const s of slots) {
          if (s.part !== 'eve' || s.off === true) continue;
          nights += 1;
          nth += 1;
          if (s.items.some((it) => it.c === 'eat')) continue;
          miss += 1;
          empty += 1;
          bump(by.base, base);
          bump(by.days, days);
          bump(by.pace, pace);
          bump(by.dow, WEEK[dowOf(addDays(start, s.day - 1))]);
          bump(by.nth, nth);
          if (examples.length < 5) examples.push(`${start} ${days} 天 住${base} ${pace} 第 ${s.day} 天晚上`);
        }
        if (miss > 0) tripsWithEmpty += 1;
      }
    }
  }
}
const pct = (a, b) => (b === 0 ? '0' : ((a / b) * 100).toFixed(1));
const show = (o) => Object.entries(o).map(([k, v]) => `${k}:${v}`).join('  ') || '（沒有）';
console.log(`趟數 ${trips}，該有晚餐的晚上 ${nights}，空著 ${empty}（${pct(empty, nights)}%），有空晚上的趟 ${tripsWithEmpty}（${pct(tripsWithEmpty, trips)}%）`);
console.log(`照住哪一帶：${show(by.base)}`);
console.log(`照天數：${show(by.days)}`);
console.log(`照節奏：${show(by.pace)}`);
console.log(`照那晚星期幾：${show(by.dow)}`);
console.log(`照這趟第幾個晚上：${show(by.nth)}`);
if (examples.length) console.log(`例子：${examples.join('；')}`);
