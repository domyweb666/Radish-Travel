// 星級與去過的站：把 PlanGenerate.swift 排第一版行程的規則用 node 照搬（從 scan-street-dinner.mjs 抄來，加上星級和去過），
// 讀真的資料包（seoul.json）、核對資料（seoul-checked.json）和 Stars.swift 的 ADDED_STAR，看排出來的有沒有道理。
// 這台沒有 Swift 編譯器，所以靠這支看規則跑出來的結果。
//
// 跑法：node ios/tools/scan-stars.mjs [出發日 YYYY-MM-DD，預設 2026-12-08]
// 會印：
//   1. 星級分布
//   2. 第一次來、住明洞、三天（上午到晚上走）排出什麼：沒說喜歡哪一類的一組、預設偏好（最愛吃）一組
//   3. 把第 2 組排到的三星都當成去過，再排一次
//   4. 掃 2 到 7 天 × 住四帶 × 三種節奏 × 一週七天：第一次來／三星都去過，三星佔幾成、排到幾站去過的
//   5. 星級加進去前後，同一組設定排出來不一樣的有幾趟（看舊測試會不會受影響）
//
// 照搬的規則跟 scan-street-dinner.mjs 一樣，另外加：
// - score 加 starBonus：第一次來（visited 空的）三星 +1.5、二星 +0.5；去過首爾以後縮成三分之一：三星 +0.5、二星 +0.25
// - areaScore 加上那一帶最好的大站的 starBonus（第一次來，景福宮那一帶先排）
// - 去過的平常不排（skipVisited），一個時段照順序都挑不到才放寬再挑一次（firstPick）；順路第二站、趕的晚上多一站不放寬
// - areaScore 不算去過的
// 簡化的：不洗牌、沒有 tweaks（帶長輩、輕鬆、想省、慶祝）。身體限制、以後都不排有照搬
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const CORE = join(HERE, '..', 'RadishCore', 'Sources', 'RadishCore');
const RES = join(CORE, 'Resources');
const DATA = JSON.parse(readFileSync(join(RES, 'seoul.json'), 'utf8'));
const CK = JSON.parse(readFileSync(join(RES, 'seoul-checked.json'), 'utf8'));

// Stars.swift 的 ADDED_STAR：直接讀 Swift 原始檔，兩邊才不會不一樣
const starsSrc = readFileSync(join(CORE, 'Stars.swift'), 'utf8');
const addedAt = starsSrc.indexOf('let ADDED_STAR');
const addedBlock = starsSrc.slice(addedAt, starsSrc.indexOf('\n]', addedAt));
const ADDED_STAR = {};
for (const m of addedBlock.matchAll(/"(p\d+[a-z]?)":\s*(\d)/g)) ADDED_STAR[m[1]] = +m[2];

const FOOD_KINDS = ['street', 'local', 'famous', 'fine'];
const CATS = ['eat', 'shop', 'fun', 'sight', 'art', 'nature', 'cafe', 'night', 'kpop'];
const PARTS = ['am', 'pm', 'eve'];
const AREAS = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'J'];
const ADJ = DATA.adj;

/* ---------- 候選地點（SeoulFacts.swift mergePlaces、placeGroup，Stars.swift withStars） ---------- */
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
const clamp = (s) => Math.min(3, Math.max(1, s));
function starOf(p) {
  if (p.star != null) return clamp(p.star);
  if (ADDED_STAR[p.id] != null) return clamp(ADDED_STAR[p.id]);
  const g = placeGroup(p.id);
  if (g !== p.id) {
    const parent = DATA.places.find((q) => q.id === g);
    if (parent?.star != null) return clamp(parent.star);
  }
  return 2;
}
const noStar = [];
for (const p of PLACES) {
  if (p.star == null && ADDED_STAR[p.id] == null) noStar.push(p.id);
  p.star = starOf(p);
}
const starBonus = (star, firstTime) => (firstTime ? (star === 3 ? 1.5 : star === 2 ? 0.5 : 0) : star === 3 ? 0.5 : star === 2 ? 0.25 : 0);

/* ---------- 日期 ---------- */
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

/* ---------- 偏好 ---------- */
function defaultSettings() {
  return {
    base: 'C', food: { street: 2, local: 3, famous: 1, fine: 0 }, walk: 'normal', body: [], learned: [],
    play: { eat: 2 }, purposes: [], pace: 'mid', wake: 'normal',
  };
}
// 以後都不排（Prefs.swift banned）：某一站（或同一組）、某一類、某一種吃的
function banned(p, st) {
  for (const l of st.learned) {
    if (l.kind === 'place' && (l.key === p.id || l.key === placeGroup(p.id))) return true;
    if (l.kind === 'cat' && l.key === p.c) return true;
    if (l.kind === 'food' && p.c === 'eat' && l.key === p.f) return true;
  }
  return false;
}
function foodLv(st) {
  const f = {};
  let any = false;
  for (const k of FOOD_KINDS) {
    f[k] = st.learned.some((l) => l.kind === 'food' && l.key === k) ? 0 : st.food[k] ?? 0;
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

/* ---------- 排一趟（PlanGenerate.swift generateBody，shuffle false） ----------
 * stars false 是星級加進去之前的排法（比對舊測試用），visited 是 { 代號: 趟數 }，facts false 是不看休館（跟測試的 closed: neverClosed 一樣），partFacts 是時段要不要看（測試只換 closed 時還是看） */
function generate(d, st, { stars = true, visited = {}, facts = true, partFacts = facts } = {}) {
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
  const firstTime = Object.keys(visited).length === 0;
  let allowVisited = false;
  const longTrip = d.days > 7;

  const score = (p) => {
    let v = w[p.c] ?? 0;
    if (wantRest && p.l === true) v += 2;
    if (st.walk === 'less' && p.l === true) v += 2;
    if (weather && outdoor(p)) v -= 3;
    if (stars) v += starBonus(p.star, firstTime);
    return v;
  };
  const skipVisited = (p) => !allowVisited && visited[p.id] != null;
  const fits = (p) => !banned(p, st) && !(noUp && p.up === true);
  const shut = (p) => {
    const f = CK.facts[p.id];
    if (!f) return false;
    const iso = addDays(d.start, today - 1);
    if (facts && closedWhy(f, iso) != null) return true;
    return partFacts && partClosed(f, iso, nowPart);
  };
  const taken = (p) => used.has(p.id) || (!sameGroupOK && usedGroup.has(placeGroup(p.id)));
  const anyOpen = (a, size) =>
    PLACES.some((p) => p.a === a && p.s === size && !taken(p) && fits(p) && !shut(p) && !skipVisited(p));
  const take = (areas, size, want, why) => {
    let best = null;
    let bestScore = 0;
    for (const p of PLACES) {
      if (!areas.includes(p.a)) continue;
      if (taken(p)) continue;
      if (!fits(p)) continue;
      if (size && p.s !== size) continue;
      if (want && !want(p)) continue;
      if (skipVisited(p)) continue;
      if (shut(p)) continue;
      const v = score(p);
      if (best == null || v > bestScore) { best = p; bestScore = v; }
    }
    if (!best) return null;
    used.add(best.id);
    usedGroup.add(placeGroup(best.id));
    if (best.c === 'eat' && nowPart !== 'eve') eatToday += 1;
    let reason = why ?? '';
    if (visited[best.id] != null) reason = visited[best.id] <= 1 ? '你上次來去過，這一帶沒別的可排' : `你之前來去過 ${visited[best.id]} 次，這一帶沒別的可排`;
    else if (why === 'pref' && firstTime && stars && best.star >= 3 && !(st.play[best.c] > 0)) reason = '估計第一次來首爾的人多半會去';
    return { ...best, why: reason };
  };
  const firstPick = (tries, again = true) => {
    for (const t of tries) { const x = t(); if (x) return x; }
    if (!again || firstTime) return null;
    allowVisited = true;
    try {
      for (const t of tries) { const x = t(); if (x) return x; }
      return null;
    } finally { allowVisited = false; }
  };
  const near = (a) => [a, ...(ADJ[a] ?? [])];
  const areaScore = (a) => {
    let sum = 0;
    let count = 0;
    let mainStar = 0;
    for (const p of PLACES) {
      if (p.a !== a || !fits(p) || visited[p.id] != null) continue;
      sum += score(p);
      count += 1;
      if (stars && p.s === 'L') mainStar = Math.max(mainStar, starBonus(p.star, firstTime));
    }
    return (count > 0 ? sum / count : 0) + mainStar;
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
        const sameGroup = () => {
          sameGroupOK = true;
          try { return take(city, 'S', eatsNow, 'same') ?? take(AREAS, 'S', eatsNow, 'same'); } finally { sameGroupOK = false; }
        };
        const dinner = firstPick([
          () => take(city, 'S', isKind, 'dinner'),
          () => take(AREAS, 'S', isKind, 'dinner'),
          () => take(city, 'S', eatsNow, 'dinner'),
          () => take(AREAS, 'S', eatsNow, 'dinner'),
          sameGroup,
        ]);
        if (dinner) items.push(dinner);
        if (pace === 'fast' && !edge) {
          const extra = take(city, 'S', (p) => p.c !== 'eat' && p.l !== true, 'fast');
          if (extra) items.push(extra);
        }
      } else if (edge) {
        const easyOK = (p) => dayOK(p) && (p.l === true || p.c === 'shop' || p.c === 'cafe' || p.c === 'eat');
        const noBookOK = (p) => dayOK(p) && p.b !== true;
        const pick = firstPick([() => take(near(a), 'S', easyOK, 'edge'), () => take(near(a), 'S', noBookOK, 'edge')], !longTrip);
        if (pick) items.push(pick);
      } else if (a === 'J') {
        if (part === 'am') {
          const far = firstPick([() => take(['J'], 'L', null, 'pref')]);
          if (far) items.push(far);
        }
      } else {
        const bigTime = part === 'am' ? st.wake !== 'late' : pace !== 'slow' || st.wake === 'late';
        const big = !lightDay && bigTime;
        const tries = [];
        if (big) tries.push(() => take([a], 'L', null, 'pref'));
        tries.push(() => take([a], 'S', dayOK, 'pref'));
        tries.push(() => take(near(a), 'S', dayOK, 'pref'));
        const pick = firstPick(tries, !longTrip);
        if (pick) items.push(pick);
        const first = items[0] ?? null;
        const firstSmallOrNone = first ? first.s === 'S' : true;
        const lessAndHas = st.walk === 'less' && first != null;
        if (pace === 'fast' || (firstSmallOrNone && pace !== 'slow' && !lessAndHas)) {
          let more = take([a], 'S', dayOK, 'same-area');
          if (!more) more = take(near(a), 'S', dayOK, 'same-area');
          if (more) items.push(more);
        }
      }
      if (d.days > 7 && part !== 'eve' && a !== 'J' && items.length === 0) {
        const notEat = (p) => p.c !== 'eat' && dayOK(p);
        const tries = [];
        sameGroupOK = true;
        if (edge) {
          tries.push(() => take(near(a), 'S', (p) => notEat(p) && (p.l === true || p.c === 'shop' || p.c === 'cafe'), 'edge'));
          tries.push(() => take(near(a), 'S', (p) => notEat(p) && p.b !== true, 'edge'));
        } else {
          tries.push(() => take([a], 'S', notEat, 'pref'));
          tries.push(() => take(near(a), 'S', notEat, 'pref'));
        }
        const fill = firstPick(tries);
        sameGroupOK = false;
        if (fill) items.push(fill);
      }
      slots.push({ day, part, off: null, items });
    }
  }
  return slots;
}

/* ---------- 印 ---------- */
const PART_NAME = { am: '上午', pm: '下午', eve: '晚上' };
const stopsOf = (slots) => slots.flatMap((s) => s.items);
function show(title, slots) {
  console.log(`\n${title}`);
  for (const s of slots) {
    if (s.off) continue;
    const names = s.items.map((x) => `${x.n}（${'★'.repeat(x.star)}${x.why.startsWith('你') || x.why.startsWith('估') ? '，' + x.why : ''}）`);
    console.log(`  第 ${s.day} 天${PART_NAME[s.part]}：${names.join('、') || '（空）'}`);
  }
}
const share3 = (slots) => {
  const all = stopsOf(slots);
  return all.length ? all.filter((x) => x.star === 3).length / all.length : 0;
};
const pct = (x) => (x * 100).toFixed(1) + '%';

function main() {
const start = process.argv[2] ?? '2026-12-08';
const c = { 1: 0, 2: 0, 3: 0 };
for (const p of PLACES) c[p.star] += 1;
console.log(`[scan-stars] 候選 ${PLACES.length} 站：三星 ${c[3]}、二星 ${c[2]}、一星 ${c[1]}`);
console.log(`  三星：${PLACES.filter((p) => p.star === 3).map((p) => p.n).join('、')}`);
if (noStar.length) console.log(`  沒寫星級的（會當二星）：${noStar.join('、')}`);

const draft = { start, days: 3, arrive: 'am', leave: 'eve', base: 'C' };
const st = defaultSettings();
// 預設偏好是「最愛吃」（play eat 2），吃的分數比星級大，所以白天常排吃的。另外看一組沒說喜歡哪一類的
show(`第一次來、沒說喜歡哪一類、住明洞、${start} 起三天：`, generate(draft, { ...st, play: {} }));
const first = generate(draft, st);
show(`第一次來、預設偏好、住明洞、${start} 起三天：`, first);
const been = {};
for (const x of stopsOf(first)) if (x.star === 3) been[x.id] = 1;
console.log(`\n  當成去過：${stopsOf(first).filter((x) => been[x.id]).map((x) => x.n).join('、')}`);
show('同樣三天，上面那幾個三星都去過了：', generate(draft, st, { visited: been }));
const all3 = {};
for (const p of PLACES) if (p.star === 3) all3[p.id] = 1;
show('同樣三天，三星全部去過：', generate(draft, st, { visited: all3 }));

// 掃
let n = 0;
let firstShare = 0;
let againShare = 0;
let visitedPicked = 0;
let changed = 0;
const BASES = Object.keys(DATA.hotel);
for (const pace of ['slow', 'mid', 'fast']) {
  for (let days = 2; days <= 7; days++) {
    for (const base of BASES) {
      for (let o = 0; o < 7; o++) {
        const s = { ...defaultSettings(), pace };
        const d = { start: addDays(start, o), days, arrive: 'am', leave: 'eve', base };
        const a = generate(d, s);
        const b = generate(d, s, { visited: all3 });
        const old = generate(d, s, { stars: false });
        n += 1;
        firstShare += share3(a);
        againShare += share3(b);
        visitedPicked += stopsOf(b).filter((x) => all3[x.id]).length;
        if (JSON.stringify(stopsOf(a).map((x) => x.id)) !== JSON.stringify(stopsOf(old).map((x) => x.id))) changed += 1;
      }
    }
  }
}
console.log(`\n掃 ${n} 趟（2 到 7 天 × 住 ${BASES.join('、')} × 三種節奏 × 一週七天，預設偏好）：`);
console.log(`  第一次來，三星佔 ${pct(firstShare / n)}；三星全部去過，三星佔 ${pct(againShare / n)}，排到去過的共 ${visitedPicked} 站`);
console.log(`  跟星級加進去之前比，排出來的站不一樣的有 ${changed} 趟（${pct(changed / n)}）`);

}

// 直接跑才印；被別的腳本 import 時只拿 generate 用
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();

export { generate, PLACES, defaultSettings, addDays, stopsOf, show };
