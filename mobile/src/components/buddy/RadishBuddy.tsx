// 蘿蔔人：戴蘿蔔頭套的火柴人。頭套和臉用 theme.ts 的角色色；身體線條跟著文字色，深色模式才看得到。
// 動作在 poses.ts。這裡只管畫，和每一格往前推時間。
// 開著「減少動態效果」時不播，停在最好認的那一格。
import { useEffect, useRef, useState } from 'react';
import { View } from 'react-native';
import Svg, { Circle, Ellipse, G, Line, Path, Rect } from 'react-native-svg';
import { T, useDomy } from '@domy/design';
import { buddyColors as B, radishColors as R } from '../../theme';
import { RIG, STILL_AT, blend, poseAt, skeleton, type BuddyAction, type PointDir, type Pose, type Pt } from './poses';

/** 常用的三種大小，從設計代號算出來 */
export const BUDDY_SIZE = {
  /** 開場、空畫面的主角 */
  hero: T.space[12] * 3,
  /** 卡片裡陪在旁邊 */
  card: T.space[12] * 1.5,
  /** 對話頭像 */
  avatar: T.size.touch,
} as const;

const BOX = {
  full: { x: 50, y: -20, w: 220, h: 420 },
  bust: { x: 85, y: 12, w: 150, h: 190 },
};
const BLEND = 0.28; // 換動作的過渡秒數
const FRAME = 1 / 30; // 一秒畫 30 格就夠，省電

const HOOD = 'M0,4 C-22,2 -46,-18 -46,-52 C-46,-84 -24,-102 0,-102 C24,-102 46,-84 46,-52 C46,-18 22,2 0,4 Z';
const LEAF_L = 'M-2,-97 C-22,-106 -35,-126 -31,-146 C-14,-138 -4,-120 -2,-97 Z';
const LEAF_M = 'M0,-97 C-11,-122 -7,-146 2,-160 C12,-145 12,-121 0,-97 Z';
const LEAF_R = 'M2,-97 C6,-120 18,-137 35,-143 C37,-124 24,-105 2,-97 Z';

function Limb({ pts, w, color }: { pts: Pt[]; w: number; color: string }) {
  return (
    <>
      {pts.slice(1).map((b, i) => (
        <Line key={i} x1={pts[i][0]} y1={pts[i][1]} x2={b[0]} y2={b[1]} stroke={color} strokeWidth={w} strokeLinecap="round" />
      ))}
    </>
  );
}

function Head({ p }: { p: Pose }) {
  const ex = p.lookX;
  const ey = p.lookY;
  const mx = ex * 0.5;
  const my = -30 + ey * 0.5;
  const drip = (p.t * 0.9) % 1;
  return (
    <>
      <Path d={LEAF_L} fill={R.leaf} />
      <Path d={LEAF_R} fill={R.leaf} />
      <Path d={LEAF_M} fill={B.leafDark} />
      <Path d={HOOD} fill={R.small} />
      <Path d="M-33,-74 C-24,-88 -12,-95 2,-96" fill="none" stroke={B.shine} strokeWidth={5} strokeLinecap="round" />
      <Path d="M30,-22 h9 M-40,-30 h8" stroke={R.smallLine} strokeWidth={3} strokeLinecap="round" />
      <Circle cx={0} cy={-46} r={33} fill={B.faceRim} />
      <Circle cx={0} cy={-46} r={30} fill={B.face} stroke={B.ink} strokeWidth={3} />
      {[-1, 1].map((sx) => {
        const cx = sx * 11 + ex;
        const cy = -48 + ey;
        const h = Math.max(1.5, p.eyeH);
        const bx = sx * 12 + ex * 0.5;
        const by = -61 + p.browY + ey * 0.5;
        const br = (p.brow * Math.PI) / 180;
        const c = 8 * Math.cos(br);
        const sn = 8 * Math.sin(br);
        return (
          <G key={sx}>
            {p.happy > 0.5 ? (
              <Path d={`M${cx - 5},${cy + 3} Q${cx},${cy - 6} ${cx + 5},${cy + 3}`} fill="none" stroke={B.ink} strokeWidth={3.6} strokeLinecap="round" />
            ) : (
              <Rect x={cx - 2.3} y={cy - h / 2} width={4.6} height={h} rx={2.3} fill={B.ink} />
            )}
            <Line x1={bx - sx * c} y1={by + sn} x2={bx + sx * c} y2={by - sn} stroke={B.ink} strokeWidth={3.4} strokeLinecap="round" />
          </G>
        );
      })}
      {p.mouth === 'smile' ? (
        <Path d={`M${mx - 6},${my - 1} Q${mx},${my + 5} ${mx + 6},${my - 1}`} fill="none" stroke={B.ink} strokeWidth={3} strokeLinecap="round" />
      ) : p.mouth === 'open' ? (
        <Path d={`M${mx - 7},${my - 2} Q${mx},${my + 10} ${mx + 7},${my - 2} Z`} fill={B.ink} />
      ) : p.mouth === 'wavy' ? (
        <Path d={`M${mx - 7},${my} q3.5,-4 7,0 t7,0`} fill="none" stroke={B.ink} strokeWidth={3} strokeLinecap="round" />
      ) : p.mouth === 'o' ? (
        <Circle cx={mx} cy={my} r={2.6} fill="none" stroke={B.ink} strokeWidth={2.6} />
      ) : (
        <Line x1={mx - 5} y1={my} x2={mx + 5} y2={my} stroke={B.ink} strokeWidth={3} strokeLinecap="round" />
      )}
      {p.sweat > 0.5 ? <Path d={`M-21,${-66 + drip * 6} q-4,7 0,9 q4,-2 0,-9 Z`} fill={B.sweat} opacity={1 - drip * 0.6} /> : null}
    </>
  );
}

function Figure({ p, crop, line }: { p: Pose; crop: 'full' | 'bust'; line: string }) {
  const k = skeleton(p);
  const sy = 1 - p.squash;
  const sx = 1 + p.squash * 0.6;
  const shrink = 1 - k.lift * 0.35;
  return (
    <>
      {crop === 'full' ? <Ellipse cx={RIG.hipX} cy={RIG.ground + 7} rx={62 * shrink} ry={8 * shrink} fill={line} opacity={0.16 * (1 - k.lift * 0.5)} /> : null}
      <G transform={`translate(${RIG.hipX},${RIG.ground}) scale(${sx},${sy}) translate(${-RIG.hipX},${-RIG.ground})`}>
        {k.legs.map((l, i) => (
          <Limb key={i} pts={l} w={9} color={line} />
        ))}
        <Limb pts={[k.hip, k.neck]} w={9} color={line} />
        <G transform={`translate(${k.head.x},${k.head.y}) rotate(${k.head.rot}) scale(1,${k.head.scaleY})`}>
          <Head p={p} />
        </G>
        {k.arms.map((a, i) => (
          <Limb key={i} pts={a} w={8.5} color={line} />
        ))}
        {p.bubble > 0.5
          ? ([[-58, -104, 4], [-70, -120, 5.5], [-86, -140, 7.5]] as const).map(([dx, dy, r], i) => (
              <Circle key={i} cx={k.neck[0] + dx} cy={k.neck[1] + dy} r={r} fill={R.smallLine} opacity={0.35 + 0.65 * Math.max(0, Math.sin(p.t * 3 - i * 0.9))} />
            ))
          : null}
      </G>
    </>
  );
}

/**
 * 蘿蔔人。action 換了會自己用 0.28 秒過渡過去。
 * 它是裝飾，VoiceOver 會跳過；要讓人知道的事請寫在旁邊的文字裡。
 */
export function RadishBuddy({
  action = 'idle',
  dir = 'right',
  size = BUDDY_SIZE.card,
  crop = 'full',
}: {
  action?: BuddyAction;
  dir?: PointDir;
  /** 高度。寬度照比例算 */
  size?: number;
  /** full 是全身，bust 是頭和肩膀（頭像用） */
  crop?: 'full' | 'bust';
}) {
  const { reduceMotion, c } = useDomy();
  const [pose, setPose] = useState<Pose>(() => poseAt(action, STILL_AT[action], dir));
  const st = useRef({ clock: 0, start: 0, switchAt: -1, from: pose, shown: pose, action, dir });

  useEffect(() => {
    const s = st.current;
    if (reduceMotion) {
      const p = poseAt(action, STILL_AT[action], dir);
      s.shown = p;
      setPose(p);
      return;
    }
    if (s.action !== action || s.dir !== dir) {
      s.from = s.shown;
      s.switchAt = s.clock;
      s.start = s.clock;
      s.action = action;
      s.dir = dir;
    }
    let raf = 0;
    let last: number | null = null;
    let acc = 0;
    const tick = (ts: number) => {
      if (last == null) last = ts;
      const dt = Math.min(0.1, (ts - last) / 1000);
      last = ts;
      s.clock += dt;
      acc += dt;
      if (acc >= FRAME) {
        acc = 0;
        let p = poseAt(s.action, s.clock - s.start, s.dir);
        if (s.switchAt >= 0) {
          const k = (s.clock - s.switchAt) / BLEND;
          if (k < 1) p = blend(s.from, p, k * k * (3 - 2 * k));
          else s.switchAt = -1;
        }
        s.shown = p;
        setPose(p);
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [action, dir, reduceMotion]);

  const b = BOX[crop];
  const w = (size * b.w) / b.h;
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      style={{ width: w, height: size }}
    >
      <Svg width={w} height={size} viewBox={`${b.x} ${b.y} ${b.w} ${b.h}`}>
        <Figure p={pose} crop={crop} line={c.textPrimary} />
      </Svg>
    </View>
  );
}

/** 播一下某個動作再回到平常的樣子。例：按「拔起來」之後歡呼一秒半 */
export function useBuddyBurst(base: BuddyAction = 'idle'): [BuddyAction, (a: BuddyAction, seconds?: number) => void] {
  const [action, setAction] = useState<BuddyAction>(base);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => void (timer.current && clearTimeout(timer.current)), []);
  const play = (a: BuddyAction, seconds = 1.6) => {
    if (timer.current) clearTimeout(timer.current);
    setAction(a);
    timer.current = setTimeout(() => setAction(base), seconds * 1000);
  };
  return [action, play];
}
