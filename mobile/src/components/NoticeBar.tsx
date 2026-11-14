// 提示條：做完一個動作後告訴你發生了什麼，可以復原的會帶一顆「復原」。浮在分頁列上方。
import { Pressable, View } from 'react-native';
import { DomyText, T, elevation, hitSlopFor, useDomy, useTabBarClearance } from '@domy/design';
import { useApp } from '../store';

export function NoticeBar() {
  const { c } = useDomy();
  const { notice, undo, dismissNotice } = useApp();
  const clearance = useTabBarClearance();
  if (!notice) return null;
  return (
    <View pointerEvents="box-none" style={{ position: 'absolute', left: T.size.screenMargin, right: T.size.screenMargin, bottom: clearance, alignItems: 'center' }}>
      <View
        accessibilityLiveRegion="polite"
        style={[
          {
            flexDirection: 'row',
            alignItems: 'center',
            gap: T.space[3],
            backgroundColor: c.textPrimary,
            borderRadius: T.radius.lg,
            paddingVertical: T.space[3],
            paddingHorizontal: T.space[4],
            maxWidth: '100%',
          },
          elevation(2, c.shadow),
        ]}
      >
        <DomyText variant="subheadline" style={{ color: c.surface, flexShrink: 1 }}>
          {notice.text}
        </DomyText>
        {notice.canUndo ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="復原"
            hitSlop={hitSlopFor(T.type.callout.lineHeight)}
            onPress={() => {
              dismissNotice();
              undo();
            }}
          >
            <DomyText variant="callout" style={{ color: c.bright }}>
              復原
            </DomyText>
          </Pressable>
        ) : null}
      </View>
    </View>
  );
}
