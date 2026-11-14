export type Part = 'am' | 'pm' | 'eve';
export type Cat = 'eat' | 'shop' | 'fun' | 'sight' | 'art' | 'nature' | 'cafe' | 'night' | 'kpop';
export type FoodKind = 'street' | 'local' | 'famous' | 'fine';
export type IconKey = Cat | 'market' | 'spa' | 'boat' | 'view' | 'pin';
export type AreaKey = 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'I' | 'K' | 'J';
export type BaseKey = 'C' | 'D' | 'G' | 'I';
export type Purpose = 'rest' | 'eat' | 'fun' | 'see';
export type Size = 'L' | 'S';

export interface Place {
  id: string;
  n: string; // 中文名
  kr: string; // 當地文字名
  a: AreaKey;
  s: Size; // L 大站、S 小站
  c: Cat;
  lat: number;
  lng: number;
  b?: boolean; // 要先訂
  fee?: number; // 粗估 NT$
  tip?: string; // 須知
  l?: boolean; // 輕鬆
  f?: FoodKind;
  ic?: IconKey;
}

export interface Stop {
  id: string;
  n: string;
  kr: string;
  a: AreaKey | '';
  s: Size;
  c: Cat;
  lat: number | null;
  lng: number | null;
  b?: boolean;
  fee?: number;
  tip?: string;
  l?: boolean;
  f?: FoodKind;
  ic?: IconKey;
  status: 'kept' | 'pulled';
  swaps: number;
  why: string; // 為什麼排這一站
  say?: string; // 那一句
  mine?: boolean; // 自己加的
  ai?: boolean; // AI 加的
}

export interface Slot {
  day: number;
  part: Part;
  off?: boolean; // 在路上，不能排
  rest: boolean; // 留白
  items: Stop[];
}

export interface TripDraft {
  purpose: Purpose;
  start: string; // YYYY-MM-DD
  days: number;
  arrive: Part;
  leave: Part;
  people: number;
}

export interface Trip extends TripDraft {
  slots: Slot[];
  flight: number;
}

export type Pace = 'slow' | 'mid' | 'fast';

export interface Settings {
  stay: 'cheap' | 'mid' | 'nice';
  base: BaseKey;
  food: Record<FoodKind, number>; // 0 不要、1 偶爾、2 常常、3 主力
  avoid: string[];
  queue: 'no' | 'some' | 'any';
  mealMax: number; // 0 是不限
  budget: number; // 一天吃喝
  play: Partial<Record<Cat, 1 | 2>>;
  pace: Pace;
  wake: 'early' | 'normal' | 'late';
  move: 'transit' | 'taxi' | 'walk';
  tuned: boolean; // 使用者自己回答過偏好了嗎
}

export interface Seed {
  id: string;
  n: string;
  a: string;
  why: string;
  stop?: Stop;
  from?: { day: number; part: Part };
}

export interface BasketItem {
  n: string;
  s: Size;
  c: Cat;
  ic?: IconKey;
  say?: string;
}
export interface Basket {
  id: string;
  title: string;
  items: BasketItem[];
}

export interface ChatMsg {
  r: 'me' | 'ai' | 'sys';
  t: string;
  changes?: string[];
}

export interface AppState {
  settings: Settings;
  trip: Trip | null;
  seeds: Seed[];
  pool: string[]; // 順路可去
  checks: Record<string, boolean>;
  chat: ChatMsg[];
  baskets: Basket[];
  settingsDirty: boolean; // 設定改過、還沒套到這趟
  aiConsent: boolean;
  debugDay: number | null; // 測試用：假裝今天是第幾天
}

export type Op =
  | { op: 'move'; id: string; day: number; part: Part }
  | { op: 'swapParts'; day: number; a: Part; b: Part }
  | { op: 'swapDays'; a: number; b: number }
  | { op: 'remove'; id: string }
  | { op: 'add'; day: number; part: Part; id?: string; place?: AiPlace }
  | { op: 'replace'; id: string; with: string | AiPlace }
  | { op: 'rest'; day: number; part: Part; on: boolean };

export interface AiPlace {
  n: string;
  kr?: string;
  c?: string;
  s?: string;
  tip?: string;
  lat?: number;
  lng?: number;
}
