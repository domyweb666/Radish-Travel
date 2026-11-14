// 蘿蔔與蘿蔔田。蘿蔔是角色，顏色用 theme.ts 的角色色；田的格子用介面色。
// 現在是占位的向量圖，之後換成黏土插圖。
import { View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { DomyText, T, useDomy } from '@domy/design';
import { PART } from '../data/seoul';
import { PARTS } from '../domain/plan';
import type { Size, Trip } from '../domain/types';
import { radishColors as R } from '../theme';

const LEAF = 'M12 12C9 9 6 6 5 2c4 1 6 4 7 8 1-4 3-7 7-8-1 4-4 7-7 10z';
const BODY_L = 'M6 14c0-3 3-4 6-4s6 1 6 4c0 8-3 18-6 18S6 22 6 14z';
const BODY_S = 'M7 15c0-2 2-3 5-3s5 1 5 3c0 6-3 16-5 16S7 21 7 15z';
const DIM = { L: { w: 26, h: 37 }, S: { w: 20, h: 28 } };
const HOLE = 60;

/** 大站是白蘿蔔、比較大；小站是橘蘿蔔、比較小 */
export function Radish({ size, scale = 1, faded = false }: { size: Size; scale?: number; faded?: boolean }) {
  const d = DIM[size];
  return (
    <Svg width={d.w * scale} height={d.h * scale} viewBox="0 0 24 34" opacity={faded ? T.motion.pressedOpacity : 1} accessibilityElementsHidden importantForAccessibility="no">
      <Path d={LEAF} fill={R.leaf} />
      {size === 'L' ? (
        <>
          <Path d={BODY_L} fill={R.big} stroke={R.bigLine} strokeWidth={1.2} />
          <Path d="M9 17h3M13 22h2" stroke={R.bigLine} strokeWidth={1} strokeLinecap="round" />
        </>
      ) : (
        <>
          <Path d={BODY_S} fill={R.small} />
          <Path d="M9.5 18h3M12 23h2.5" stroke={R.smallLine} strokeWidth={1} strokeLinecap="round" />
        </>
      )}
    </Svg>
  );
}

/** 整趟的總覽：一天一列，上午、下午、晚上三格。只給看，不能點；要改去下面每一天的列 */
export function RadishField({ trip, today }: { trip: Trip; today?: number }) {
  const { c } = useDomy();
  const days = Array.from({ length: trip.days }, (_, i) => i + 1);
  const kept = trip.slots.reduce((n, s) => n + s.items.filter((i) => i.status === 'kept').length, 0);
  return (
    <View accessible accessibilityLabel={`蘿蔔田：${trip.days} 天，還有 ${kept} 站沒去`} style={{ gap: T.space[2] }}>
      <View style={{ flexDirection: 'row', gap: T.space[2] }}>
        <View style={{ width: T.space[8] }} />
        {PARTS.map((p) => (
          <DomyText key={p} variant="caption" tone="secondary" style={{ flex: 1, textAlign: 'center' }}>
            {PART[p]}
          </DomyText>
        ))}
      </View>
      {days.map((d) => (
        <View key={d} style={{ flexDirection: 'row', gap: T.space[2], alignItems: 'center' }}>
          <DomyText variant="footnote" weight="600" tone={today === d ? 'strong' : 'secondary'} style={{ width: T.space[8] }}>
            D{d}
          </DomyText>
          {PARTS.map((p) => {
            const s = trip.slots.find((x) => x.day === d && x.part === p);
            const items = s ? s.items.filter((i) => i.status === 'kept').slice(0, 3) : [];
            return (
              <View
                key={p}
                style={{
                  flex: 1,
                  height: HOLE,
                  borderRadius: T.radius.md,
                  backgroundColor: s?.off ? 'transparent' : c.surfaceMuted,
                  borderWidth: today === d ? T.size.hairline * 2 : 0,
                  borderColor: c.accent,
                  flexDirection: 'row',
                  alignItems: 'flex-end',
                  justifyContent: 'center',
                  gap: T.space[1] / 2,
                  paddingBottom: T.space[1],
                  overflow: 'hidden',
                }}
              >
                {s?.off ? (
                  <DomyText variant="caption" tone="disabled" style={{ alignSelf: 'center' }}>
                    在路上
                  </DomyText>
                ) : items.length ? (
                  items.map((it) => <Radish key={it.id} size={it.s} />)
                ) : (
                  <DomyText variant="caption" tone="secondary" style={{ alignSelf: 'center' }}>
                    {s?.rest ? '留白' : ''}
                  </DomyText>
                )}
              </View>
            );
          })}
        </View>
      ))}
      <DomyText variant="footnote" tone="secondary">
        一顆蘿蔔是一站。白的大顆是大站，要花半天；橘的小顆是小站。
      </DomyText>
    </View>
  );
}
