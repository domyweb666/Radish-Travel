// 偏好裡會改變排法的幾件事：這趟臨時調整、從行程學到的「以後都不排」、過敏告知卡。
// 純函式，不碰畫面。plan.ts 排行程時會用這裡的東西。
import { ALLERGENS, CAT, FOOD } from '../data/seoul';
import type { Cat, FoodKind, Learned, Place, Settings, Stop, Tweak } from './types';

const FOOD_KINDS = Object.keys(FOOD) as FoodKind[];
const SAVE_BUDGET = 1000;

/** 這趟實際拿來排的偏好：平常的你，加上這趟的臨時調整。不會改到傳進來的那份 */
export function tripSettings(st: Settings, tweaks: Tweak[] | undefined): Settings {
  if (!tweaks?.length) return st;
  const out: Settings = { ...st, food: { ...st.food }, body: [...st.body] };
  if (tweaks.includes('elder')) {
    out.walk = 'less';
    if (!out.body.includes('stairs')) out.body.push('stairs');
    if (out.pace === 'fast') out.pace = 'mid';
  }
  if (tweaks.includes('easy')) out.pace = out.pace === 'fast' ? 'mid' : 'slow';
  if (tweaks.includes('save')) {
    out.food.fine = 0;
    out.food.famous = Math.min(out.food.famous, 1);
    out.stay = 'cheap';
    out.budget = Math.min(out.budget, SAVE_BUDGET);
  }
  return out;
}

/* ---------- 從行程學到的 ---------- */
type Bannable = Pick<Place, 'id' | 'c' | 'f'>;

/** 這個地方是不是使用者說過以後都不排的 */
export function banned(p: Bannable, st: Settings): boolean {
  return st.learned.some((l) => (l.kind === 'place' && l.key === p.id) || (l.kind === 'cat' && l.key === p.c) || (l.kind === 'food' && p.c === 'eat' && l.key === p.f));
}

export const bannedFood = (st: Settings) => new Set(st.learned.filter((l) => l.kind === 'food').map((l) => l.key as FoodKind));

export type LearnChoice = Pick<Learned, 'kind' | 'key' | 'n'>;

/** 拿掉這一站時，可以順便記成「以後都不排」的選項。自己加的、AI 加的站不在候選裡，沒有東西可以記 */
export function learnChoices(it: Stop, st: Settings): LearnChoice[] {
  if (it.mine || it.ai || !it.a) return [];
  const out: LearnChoice[] = [{ kind: 'place', key: it.id, n: it.n }];
  if (it.c !== 'eat') out.push({ kind: 'cat', key: it.c, n: CAT[it.c] });
  else if (it.f) {
    // 吃的照種類記。只剩這一種還在吃的話不給記，不然晚餐排不出來
    const left = FOOD_KINDS.filter((k) => st.food[k] > 0 && !bannedFood(st).has(k));
    if (left.length > 1 && left.includes(it.f)) out.push({ kind: 'food', key: it.f, n: FOOD[it.f].name });
  }
  return out.filter((c) => !st.learned.some((l) => l.kind === c.kind && l.key === c.key));
}

let seq = 0;
export function learn(st: Settings, c: LearnChoice, source: string): Learned {
  const x: Learned = { ...c, id: `l${Date.now().toString(36)}${(seq++).toString(36)}`, source };
  st.learned = [x, ...st.learned.filter((l) => !(l.kind === c.kind && l.key === c.key))];
  return x;
}

export function unlearn(st: Settings, id: string): Learned | undefined {
  const x = st.learned.find((l) => l.id === id);
  if (x) st.learned = st.learned.filter((l) => l.id !== id);
  return x;
}

export const learnedText = (l: Pick<Learned, 'kind' | 'n'>) => (l.kind === 'place' ? `不排「${l.n}」` : `不排「${l.n}」這一類`);

/* ---------- 天氣和身體 ---------- */
/** 出發那個月在首爾算熱還是冷。只看月份，不是天氣預報 */
export function seasonOf(start: string): 'hot' | 'cold' | null {
  const m = Number(start.slice(5, 7));
  if (m >= 6 && m <= 9) return 'hot';
  if (m === 12 || m <= 2) return 'cold';
  return null;
}

/** 大部分時間在戶外的地方：公園散步那一類，和近郊 */
export const outdoor = (p: Pick<Place, 'c' | 'a'>) => p.c === 'nature' || p.a === 'J';

/* ---------- 過敏告知卡 ---------- */
export interface AllergyCard {
  kr: string;
  zh: string;
}

/** 給店員看的韓文告知卡。韓文是照常見說法寫的，還沒請懂韓文的人核對 */
export function allergyCard(list: string[]): AllergyCard | null {
  const hit = ALLERGENS.filter((a) => list.includes(a.n));
  if (!hit.length) return null;
  const kr = hit.map((a) => a.kr).join(', ');
  const zh = hit.map((a) => a.n).join('、');
  return {
    kr: `저는 음식 알레르기가 있습니다.\n${kr}\n을(를) 먹으면 안 됩니다.\n이 음식에 들어 있나요?\n육수나 소스에 조금 들어간 것도 안 됩니다.`,
    zh: `我有食物過敏，不能吃：${zh}。請問這道菜裡面有嗎？湯底或醬料裡只有一點點也不行。`,
  };
}

export const catName = (k: Cat) => CAT[k];
