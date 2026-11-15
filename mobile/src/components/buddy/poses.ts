// 蘿蔔人的姿勢。身體是八個關節角度，每個動作是角度隨時間變化的一組數值。
// 純計算，不碰畫面，tests/buddy.test.ts 會驗。
// 角度：0 是垂直向下，正值往畫面右邊轉。手肘和膝蓋是相對於上一節的角度。
//
// 不做的動作：大慶祝（連續天數里程碑）、打瞌睡（催人回來）。這兩個違反「不做成癮機制」。

export type BuddyAction = 'idle' | 'wave' | 'point' | 'think' | 'cheer' | 'shrug' | 'oops' | 'bow';
export type PointDir = 'up' | 'right' | 'down' | 'left';
export type Mouth = 'smile' | 'open' | 'wavy' | 'o' | 'flat';

export interface Pose {
  ry: number; lean: number; head: number; hy: number; sh: number;
  lS: number; lE: number; rS: number; rE: number;
  lH: number; lK: number; rH: number; rK: number;
  eyeH: number; lookX: number; lookY: number; brow: number; browY: number;
  squash: number; tl: number; hs: number;
  happy: number; bubble: number; sweat: number;
  mouth: Mouth;
  t: number;
}

export const RIG = { hipX: 160, hipY: 260, ground: 380, thigh: 62, shin: 62, torso: 78, shoulderDrop: 12, shoulderHalf: 6, upper: 44, fore: 44 } as const;

export function basePose(): Pose {
  return {
    ry: 0, lean: 0, head: 0, hy: 0, sh: 0,
    lS: -38, lE: 143, rS: 38, rE: -143,
    lH: -14, lK: 0, rH: 14, rK: 0,
    eyeH: 12, lookX: 0, lookY: 0, brow: 2, browY: 0,
    squash: 0, tl: 1, hs: 1,
    happy: 0, bubble: 0, sweat: 0,
    mouth: 'smile',
    t: 0,
  };
}

const ss = (a: number, b: number, x: number) => {
  const k = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return k * k * (3 - 2 * k);
};

const ANIMS: Record<BuddyAction, (t: number, d: PointDir) => Partial<Pose>> = {
  // 站著也要看得出是活的：小尺寸下只有呼吸會看不到，所以身體會晃、眼睛會看、每五秒左右踮一下
  idle: (t) => {
    const b = Math.sin(t * 2.2);
    const c = t % 4.8;
    const h = c < 0.5 ? Math.sin((Math.PI * c) / 0.5) : 0;
    return {
      sh: -2.5 * b, hy: -2 * b, lean: 3 * Math.sin(t * 1.1), head: 5 * Math.sin(t * 0.9),
      lS: -38 - 5 * b, lE: 143 + 8 * b, rS: 38 + 5 * b, rE: -143 - 8 * b,
      lookX: 3 * Math.sin(t * 0.7), eyeH: t % 3.6 > 3.46 ? 1.5 : 12,
      ry: -12 * h, lH: -14 - 5 * h, lK: 14 * h, rH: 14 + 5 * h, rK: -14 * h,
    };
  },
  wave: (t) => ({
    rS: 110, rE: 40 + 22 * Math.sin(t * 9), lS: -16, lE: -6,
    head: 5 + 2 * Math.sin(t * 4.5), lean: 2, brow: 5, browY: -1, hy: -1 * Math.sin(t * 4.5),
  }),
  point: (t, d) => {
    const k = Math.sin(t * 5);
    if (d === 'right') return { brow: 4, rS: 92, rE: 0, lS: -40, lE: 100, lean: 3 + 1.5 * k, head: 3, lookX: 3 };
    if (d === 'left') return { brow: 4, lS: -92, lE: 0, rS: 40, rE: -100, lean: -3 - 1.5 * k, head: -3, lookX: -3 };
    if (d === 'up') return { brow: 4, rS: 105, rE: 62, lS: -40, lE: 100, hy: -1.5 * k, sh: -1.5 * k, head: -4, lookY: -3, lookX: 1 };
    return { brow: 4, rS: 30, rE: 8, lS: -40, lE: 100, lean: 2, head: 9 + 1.5 * k, lookY: 3.5, lookX: 2 };
  },
  think: (t) => ({
    rS: 42, rE: 165, lS: -30, lE: 120, head: -8 + 1.5 * Math.sin(t * 1.6), lean: -1.5,
    lookX: -2, lookY: -3, brow: 3, browY: -2, bubble: 1, mouth: 'flat',
  }),
  cheer: (t) => {
    const P = 0.72;
    const p = (t % P) / P;
    const h = p < 0.8 ? Math.sin((Math.PI * p) / 0.8) : 0;
    const s = p >= 0.8 ? Math.sin((Math.PI * (p - 0.8)) / 0.2) : 0;
    const w = Math.sin(t * 15);
    return {
      ry: -34 * h, squash: 0.07 * s, lS: -105, lE: -62 - 8 * w, rS: 105, rE: 62 + 8 * w,
      lH: -14 - 12 * h, lK: 34 * h, rH: 14 + 12 * h, rK: -34 * h,
      brow: -4, browY: -3, happy: 1, mouth: 'open', head: 0.9 * w,
    };
  },
  shrug: (t) => {
    const c = t % 2.4;
    const u = ss(0, 0.3, c) * (1 - ss(1.5, 1.9, c));
    return {
      sh: -6 * u, lS: -16 - 14 * u, lE: -6 - 82 * u, rS: 16 + 14 * u, rE: 6 + 82 * u,
      head: 8 * u, brow: 2 - 12 * u, browY: -3 * u, mouth: u > 0.4 ? 'wavy' : 'smile', lookY: -1 * u,
    };
  },
  oops: (t) => ({
    rS: 112, rE: 45 + 7 * Math.sin(t * 12), lS: -16, lE: -6, head: 9, lean: 2,
    brow: -12, browY: -1, lookY: 3, lookX: -1, mouth: 'wavy', sweat: 1,
  }),
  bow: (t) => {
    const c = t % 2.6;
    const u = ss(0, 0.45, c) * (1 - ss(1.5, 2.0, c));
    return {
      lS: -12, lE: -4, rS: 12, rE: 4, tl: 1 - 0.3 * u, hs: 1 - 0.14 * u, hy: 8 * u, lookY: 6 * u,
      eyeH: 12 - 10.5 * ss(0.4, 0.8, u), brow: 2, browY: 2 * u,
    };
  },
};

export const BUDDY_ACTIONS = Object.keys(ANIMS) as BuddyAction[];

/** 「減少動態效果」開著時不播動畫，停在每個動作最好認的那一格 */
export const STILL_AT: Record<BuddyAction, number> = { idle: 1, wave: 0.2, point: 0.3, think: 0.5, cheer: 0.29, shrug: 0.9, oops: 0.1, bow: 1 };

export function poseAt(action: BuddyAction, t: number, dir: PointDir = 'right'): Pose {
  return { ...basePose(), ...ANIMS[action](t, dir), t };
}

/** 換動作時的過渡：數值內插，嘴型這種非數值的在一半時切換 */
export function blend(a: Pose, b: Pose, k: number): Pose {
  const o = { ...b } as Record<string, unknown>;
  const av = a as unknown as Record<string, unknown>;
  const bv = b as unknown as Record<string, unknown>;
  for (const key of Object.keys(bv)) {
    const x = av[key];
    const y = bv[key];
    o[key] = typeof x === 'number' && typeof y === 'number' ? x + (y - x) * k : k < 0.5 ? x : y;
  }
  o.t = b.t;
  return o as unknown as Pose;
}

export type Pt = [number, number];
const dirv = (deg: number): Pt => {
  const r = (deg * Math.PI) / 180;
  return [Math.sin(r), Math.cos(r)];
};
const add = (p: Pt, v: Pt, l: number): Pt => [p[0] + v[0] * l, p[1] + v[1] * l];

export interface Skeleton {
  hip: Pt;
  neck: Pt;
  /** 腳：髖 → 膝 → 踝 → 腳尖 */
  legs: [Pt, Pt, Pt, Pt][];
  /** 手：肩 → 肘 → 手 */
  arms: [Pt, Pt, Pt][];
  /** 頭的位置與轉角 */
  head: { x: number; y: number; rot: number; scaleY: number };
  /** 離地的程度，0 是站著。影子用 */
  lift: number;
}

export function skeleton(p: Pose): Skeleton {
  const R = RIG;
  const hip: Pt = [R.hipX, R.hipY + p.ry];
  const up = dirv(180 - p.lean);
  const len = R.torso * p.tl;
  const top = add(hip, up, len);
  const sho = add(hip, up, len - R.shoulderDrop);
  sho[1] += p.sh;
  const legs = ([[p.lH, p.lK, -1], [p.rH, p.rK, 1]] as const).map(([h, k, side]) => {
    const knee = add(hip, dirv(h), R.thigh);
    const ankle = add(knee, dirv(h + k), R.shin);
    return [hip, knee, ankle, [ankle[0] + side * 12, ankle[1] + 1]] as [Pt, Pt, Pt, Pt];
  });
  const arms = ([[p.lS, p.lE, -1], [p.rS, p.rE, 1]] as const).map(([s, e, side]) => {
    const so: Pt = [sho[0] + side * R.shoulderHalf, sho[1]];
    const elbow = add(so, dirv(s), R.upper);
    return [so, elbow, add(elbow, dirv(s + e), R.fore)] as [Pt, Pt, Pt];
  });
  return {
    hip,
    neck: [top[0], top[1] + p.sh * 0.5],
    legs,
    arms,
    head: { x: top[0], y: top[1] + p.hy + p.sh * 0.5, rot: p.head + p.lean, scaleY: p.hs },
    lift: Math.max(0, -p.ry / 40),
  };
}
