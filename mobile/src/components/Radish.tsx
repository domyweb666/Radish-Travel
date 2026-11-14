// 蘿蔔。它是角色，顏色用 theme.ts 的角色色。
// 現在是占位的向量圖，之後換成黏土插圖。
import Svg, { Path } from 'react-native-svg';
import { T } from '@domy/design';
import type { Size } from '../domain/types';
import { radishColors as R } from '../theme';

const LEAF = 'M12 12C9 9 6 6 5 2c4 1 6 4 7 8 1-4 3-7 7-8-1 4-4 7-7 10z';
const BODY_L = 'M6 14c0-3 3-4 6-4s6 1 6 4c0 8-3 18-6 18S6 22 6 14z';
const BODY_S = 'M7 15c0-2 2-3 5-3s5 1 5 3c0 6-3 16-5 16S7 21 7 15z';
const DIM = { L: { w: 26, h: 37 }, S: { w: 20, h: 28 } };

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
