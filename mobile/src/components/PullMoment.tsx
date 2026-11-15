// 拔蘿蔔的那一下。按「去過了，拔起來」之後蓋滿整個畫面：
// 蘿蔔埋在土裡 → 左右搖三下（每下一個輕震）→ 用力拔出來放大（一個重震）→ 土屑飛出去 → 出現那一句（成功的震動）。
// 整段大約兩秒，點一下可以提早關掉。開著「減少動態效果」時不搖不彈，直接淡入拔好的樣子。
import * as Haptics from 'expo-haptics';
import { useEffect, useRef } from 'react';
import { Animated, Easing, Modal, Pressable, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';
import { DomyText, T, useDomy } from '@domy/design';
import type { Size } from '../domain/types';
import { radishColors as R } from '../theme';
import { BUDDY_SIZE, RadishBuddy } from './buddy/RadishBuddy';
import { Radish } from './Radish';

const W = T.size.heroRing;
const H = T.size.heroRing * 1.25;
// domy-ignore: 這一段動畫自己的節奏，只在這裡用
const MS = { fade: 160, tug: 95, settle: 220, text: 200, hold: 1100, out: 220 };
// domy-ignore: 蘿蔔放大的倍數與拔出來那一下的大小，只在這裡用
const SIZE = { radish: 6.5, pop: 1.25, rest: 1.06, scrim: 1, mark: 0.4 };
/** 埋著的時候往下沉多少、拔出來之後往上到哪 */
const BURIED = H * 0.28;
const OUT = -H * 0.2;
/** 土屑：往哪邊飛、飛多高、多大 */
const CRUMBS: Array<[number, number, number]> = [[-70, 60, 7], [-38, 92, 5], [-8, 70, 4], [30, 96, 6], [66, 58, 5], [50, 30, 4], [-56, 26, 4]];

const tap = (style: Haptics.ImpactFeedbackStyle) => void Haptics.impactAsync(style).catch(() => {});

export function PullMoment({ name, size, line, onDone }: { name: string; size: Size; line: string; onDone: () => void }) {
  const { c, reduceMotion } = useDomy();
  const fade = useRef(new Animated.Value(0)).current;
  const y = useRef(new Animated.Value(reduceMotion ? OUT : BURIED)).current;
  const tilt = useRef(new Animated.Value(0)).current;
  const scale = useRef(new Animated.Value(reduceMotion ? SIZE.rest : 1)).current;
  const crumb = useRef(new Animated.Value(0)).current;
  const text = useRef(new Animated.Value(0)).current;
  const closing = useRef(false);

  const close = () => {
    if (closing.current) return;
    closing.current = true;
    Animated.timing(fade, { toValue: 0, duration: MS.out, useNativeDriver: true }).start(() => onDone());
  };

  useEffect(() => {
    const timers: Array<ReturnType<typeof setTimeout>> = [];
    const at = (ms: number, fn: () => void) => timers.push(setTimeout(fn, ms));
    const t = (v: Animated.Value, toValue: number, duration: number, easing = Easing.out(Easing.quad)) =>
      Animated.timing(v, { toValue, duration, easing, useNativeDriver: true });

    if (reduceMotion) {
      Animated.parallel([t(fade, 1, MS.fade), t(text, 1, MS.text)]).start();
      void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      at(MS.hold + MS.fade, close);
      return () => timers.forEach(clearTimeout);
    }

    // 搖三下：每一下往上鬆一點
    const tug = (deg: number, up: number) => Animated.parallel([t(tilt, deg, MS.tug, Easing.inOut(Easing.quad)), t(y, BURIED - up, MS.tug)]);
    const wiggle = Animated.sequence([tug(-1, 8), tug(1, 16), tug(-0.7, 26), tug(0.7, 38), tug(0, 46)]);
    const pop = Animated.parallel([
      Animated.spring(y, { toValue: OUT, friction: 5, tension: 140, useNativeDriver: true }),
      Animated.sequence([t(scale, SIZE.pop, MS.tug * 1.4), t(scale, SIZE.rest, MS.settle, Easing.inOut(Easing.quad))]),
      t(crumb, 1, MS.settle * 2.4, Easing.linear),
    ]);
    Animated.sequence([t(fade, 1, MS.fade), wiggle]).start(() => {
      tap(Haptics.ImpactFeedbackStyle.Heavy);
      pop.start();
      t(text, 1, MS.text).start();
    });
    // 震動跟著搖的節奏走
    [1, 2, 3].forEach((i) => at(MS.fade + MS.tug * i, () => tap(Haptics.ImpactFeedbackStyle.Light)));
    at(MS.fade + MS.tug * 4, () => tap(Haptics.ImpactFeedbackStyle.Medium));
    const popAt = MS.fade + MS.tug * 5;
    at(popAt + MS.settle + MS.tug, () => void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {}));
    at(popAt + MS.settle + MS.hold, close);
    return () => timers.forEach(clearTimeout);
    // 只在出現的那一刻跑一次
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const rotate = tilt.interpolate({ inputRange: [-1, 1], outputRange: ['-9deg', '9deg'] });
  return (
    <Modal visible transparent animationType="none" onRequestClose={close} statusBarTranslucent>
      <Pressable accessibilityRole="button" accessibilityLabel={`${name}，${line}點一下關掉`} onPress={close} style={{ flex: 1 }}>
        <Animated.View style={{ position: 'absolute', top: 0, bottom: 0, left: 0, right: 0, backgroundColor: c.canvas, opacity: Animated.multiply(fade, SIZE.scrim) }} />
        <Animated.View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: T.space[5], padding: T.space[6], opacity: fade }}>
          <View style={{ width: W, height: H, alignItems: 'center', justifyContent: 'flex-end' }}>
            <Animated.View style={{ position: 'absolute', bottom: H * 0.3, transform: [{ translateY: y }, { rotate }, { scale }] }}>
              <Radish size={size} scale={SIZE.radish} />
            </Animated.View>
            {/* 土丘畫在蘿蔔前面，蓋住埋著的那一截 */}
            <Svg width={W} height={H * 0.34} viewBox="0 0 216 92">
              <Path d="M0,92 L0,56 C24,22 70,6 108,6 C146,6 192,22 216,56 L216,92 Z" fill={R.soil} />
              <Path d="M56,40 h14 M132,30 h18 M96,58 h10 M160,60 h12" stroke={R.smallLine} strokeWidth={3} strokeLinecap="round" opacity={SIZE.mark} />
            </Svg>
            {CRUMBS.map(([dx, dy, r], i) => (
              <Animated.View
                key={i}
                style={{
                  position: 'absolute',
                  bottom: H * 0.3,
                  opacity: crumb.interpolate({ inputRange: [0, 0.05, 0.7, 1], outputRange: [0, 1, 1, 0] }),
                  transform: [
                    { translateX: crumb.interpolate({ inputRange: [0, 1], outputRange: [0, dx] }) },
                    { translateY: crumb.interpolate({ inputRange: [0, 0.45, 1], outputRange: [0, -dy, dy * 0.4] }) },
                  ],
                }}
              >
                <Svg width={r * 2} height={r * 2}>
                  <Circle cx={r} cy={r} r={r} fill={R.soil} />
                </Svg>
              </Animated.View>
            ))}
          </View>
          <Animated.View style={{ alignItems: 'center', gap: T.space[2], opacity: text, transform: [{ translateY: text.interpolate({ inputRange: [0, 1], outputRange: [T.space[3], 0] }) }] }}>
            <DomyText variant="title1" style={{ textAlign: 'center' }}>
              {line}
            </DomyText>
            <DomyText variant="headline" tone="strong" style={{ textAlign: 'center' }}>
              {name}
            </DomyText>
            <RadishBuddy action="cheer" size={BUDDY_SIZE.card} />
          </Animated.View>
        </Animated.View>
      </Pressable>
    </Modal>
  );
}
