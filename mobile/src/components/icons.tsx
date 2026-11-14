// 圖示：分頁列四個、地點種類十四個。種類只靠形狀分，底色統一用產品色的 Soft。
import { View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { T, useDomy } from '@domy/design';
import type { IconKey, Stop } from '../domain/types';

const STROKE = 2;
const TAB = 22;

function Line({ d, color, size = TAB }: { d: string; color: string; size?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none" accessibilityElementsHidden importantForAccessibility="no">
      <Path d={d} stroke={color} strokeWidth={STROKE} strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  );
}

export const TabTrip = ({ color }: { color: string }) => <Line color={color} d="M6 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM18 8a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM8 18h6a3 3 0 0 0 0-6h-4a3 3 0 0 1 0-6h6" />;
export const TabPrep = ({ color }: { color: string }) => <Line color={color} d="M9 6h11M9 12h11M9 18h11M4 6l1 1 1.5-2M4 12l1 1 1.5-2M4 18l1 1 1.5-2" />;
export const TabBasket = ({ color }: { color: string }) => <Line color={color} d="M4 10h16l-1.5 9h-13zM8 10l3-6M16 10l-3-6M9 14v2M12 14v2M15 14v2" />;
export const TabMe = ({ color }: { color: string }) => <Line color={color} d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0" />;
export const IconSend = ({ color }: { color: string }) => <Line color={color} d="M12 19V5M5 12l7-7 7 7" />;
export const IconSprout = ({ color }: { color: string }) => <Line color={color} d="M12 21v-9M12 14c-5 0-7-3-7-7 5 0 7 3 7 7zM12 11c0-4 2-6 7-6 0 4-2 6-7 6z" />;

const CAT_ICON: Record<IconKey, { name: string; d: string }> = {
  eat: { name: '餐廳', d: 'M7 3v8M5 3v4a2 2 0 0 0 4 0V3M7 11v10M16 21V3c-2 2-3 5-2 9h2' },
  market: { name: '市場', d: 'M4 9l1-5h14l1 5M5 9v11h14V9M4 9c0 2.5 4 2.5 4 0 0 2.5 4 2.5 4 0 0 2.5 4 2.5 4 0 0 2.5 4 2.5 4 0M10 20v-5h4v5' },
  shop: { name: '逛街', d: 'M6 8h12l1 12H5L6 8zM9 8V6a3 3 0 0 1 6 0v2' },
  fun: { name: '遊樂與體驗', d: 'M4 7h16v3a2 2 0 0 0 0 4v3H4v-3a2 2 0 0 0 0-4V7zM14 7v10' },
  sight: { name: '古蹟地標', d: 'M3 20h18M5 20v-8M9 20v-8M15 20v-8M19 20v-8M3 12h18M12 4l9 6H3l9-6z' },
  art: { name: '博物館美術館', d: 'M4 5h16v14H4zM4 16l4-4 4 4 3-3 5 5M15 9.5h.01' },
  nature: { name: '公園', d: 'M12 21v-6M12 15a5 5 0 0 1-4-8 4 4 0 0 1 8 0 5 5 0 0 1-4 8z' },
  cafe: { name: '咖啡廳', d: 'M5 9h11v6a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4V9zM16 10h2a2 2 0 0 1 0 5h-2M8 3v3M12 3v3' },
  night: { name: '夜生活', d: 'M20 14A8 8 0 1 1 10 4a6 6 0 0 0 10 10z' },
  kpop: { name: '追星', d: 'M9 18V6l10-2v12M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zM19 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z' },
  spa: { name: '汗蒸幕與溫泉', d: 'M4 17c0 3 16 3 16 0M8 4c-1.5 2 1.5 3 0 6M12 4c-1.5 2 1.5 3 0 6M16 4c-1.5 2 1.5 3 0 6' },
  boat: { name: '遊船', d: 'M3 17l2 3h14l2-3zM5 17v-5h14v5M12 12V5l5 4' },
  view: { name: '展望台', d: 'M12 3v18M8 21h8M9.5 9h5l-1-4h-3zM10 9l-2 12M14 9l2 12' },
  pin: { name: '自己加的', d: 'M12 21s7-6 7-11a7 7 0 0 0-14 0c0 5 7 11 7 11zM12 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4z' },
};

type Kindable = Pick<Stop, 'c'> & Partial<Pick<Stop, 'ic' | 'mine'>>;
const keyOf = (it: Kindable): IconKey => (it.mine ? 'pin' : it.ic && CAT_ICON[it.ic] ? it.ic : it.c);
export const kindName = (it: Kindable) => CAT_ICON[keyOf(it)].name;

/** 地點種類圖示：Soft 底的圓，產品色線條 */
export function CatIcon({ it }: { it: Kindable }) {
  const { c } = useDomy();
  const k = keyOf(it);
  return (
    <View
      accessible
      accessibilityLabel={CAT_ICON[k].name}
      style={{ width: T.size.iconButton, height: T.size.iconButton, borderRadius: T.radius.pill, backgroundColor: c.soft, alignItems: 'center', justifyContent: 'center' }}
    >
      <Line d={CAT_ICON[k].d} color={c.strong} />
    </View>
  );
}
