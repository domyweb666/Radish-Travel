// 操作說明：把畫面蓋暗，只留一塊亮的，旁邊一張卡講這一塊是做什麼的。一次講一件事。
// 要照亮的那一塊不在畫面上時，先捲過去再量位置。
import { useEffect, useState, type ComponentRef, type RefObject } from 'react';
import { Modal, View, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { DomyButton, DomyText, T, useDomy } from '@domy/design';
import type { Scroller } from './Screen';
import { Card } from './ui';

export type SpotTarget = ComponentRef<typeof View>;

export interface SpotStep {
  target: RefObject<SpotTarget | null>;
  text: string;
}
interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

const SHADE = '#000000'; // domy-ignore: 暗幕的顏色，只在這裡用
const DIM = 0.6; // 暗幕的濃度
const SETTLE = T.motion.pressDuration * 2; // 等畫面排好、捲好再量
const PAD = T.space[2];

export function Spotlight({ steps, scroller, scrollY, onDone }: { steps: SpotStep[]; scroller: RefObject<Scroller | null>; scrollY: RefObject<number>; onDone: () => void }) {
  const { c } = useDomy();
  const insets = useSafeAreaInsets();
  const win = useWindowDimensions();
  const [i, setI] = useState(0);
  const [hole, setHole] = useState<Rect | null>(null);
  const step = steps[i];

  const next = () => {
    if (i + 1 < steps.length) setI(i + 1);
    else onDone();
  };

  useEffect(() => {
    setHole(null);
    let alive = true;
    const timers: Array<ReturnType<typeof setTimeout>> = [];
    const top = insets.top + T.space[2];
    const measure = (mayScroll: boolean) => {
      const node = step?.target.current;
      // 這一塊現在不在畫面上（例如那天沒有排站），跳過
      if (!node) return next();
      node.measureInWindow((x: number, y: number, w: number, h: number) => {
        if (!alive) return;
        if (mayScroll && (y < top || y + h > win.height * 0.55)) {
          scroller.current?.scrollTo({ y: Math.max(0, scrollY.current + y - top - T.space[8]), animated: false });
          timers.push(setTimeout(() => measure(false), SETTLE));
        } else setHole({ x, y, w, h });
      });
    };
    timers.push(setTimeout(() => measure(true), SETTLE));
    return () => {
      alive = false;
      timers.forEach(clearTimeout);
    };
  }, [i]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!step) return null;
  const shade = { position: 'absolute' as const, backgroundColor: SHADE, opacity: DIM };
  const h = hole ? { x: Math.max(0, hole.x - PAD), y: hole.y - PAD, w: Math.min(win.width, hole.w + PAD * 2), h: hole.h + PAD * 2 } : null;
  const below = h ? h.y + h.h / 2 < win.height / 2 : true;
  const last = i === steps.length - 1;

  return (
    <Modal visible transparent animationType="fade" statusBarTranslucent onRequestClose={onDone}>
      <View accessibilityViewIsModal style={{ flex: 1 }}>
        {h ? (
          <>
            <View style={[shade, { top: 0, left: 0, right: 0, height: Math.max(0, h.y) }]} />
            <View style={[shade, { top: h.y + h.h, left: 0, right: 0, bottom: 0 }]} />
            <View style={[shade, { top: h.y, left: 0, width: h.x, height: h.h }]} />
            <View style={[shade, { top: h.y, left: h.x + h.w, right: 0, height: h.h }]} />
            <View pointerEvents="none" style={{ position: 'absolute', top: h.y, left: h.x, width: h.w, height: h.h, borderRadius: T.radius.md, borderWidth: T.size.hairline * 3, borderColor: c.bright }} />
            <View style={[{ position: 'absolute', left: T.size.screenMargin, right: T.size.screenMargin }, below ? { top: h.y + h.h + T.space[3] } : { bottom: win.height - h.y + T.space[3] }]}>
              <Card>
                <DomyText variant="footnote" tone="secondary">
                  {i + 1}／{steps.length}
                </DomyText>
                <DomyText variant="body">{step.text}</DomyText>
                <DomyButton title={last ? '知道了' : '下一個'} fullWidth onPress={next} />
                {last ? null : <DomyButton title="不用看了" variant="plain" size="compact" style={{ alignSelf: 'center' }} onPress={onDone} />}
              </Card>
            </View>
          </>
        ) : (
          <View style={[shade, { top: 0, left: 0, right: 0, bottom: 0 }]} />
        )}
      </View>
    </Modal>
  );
}
