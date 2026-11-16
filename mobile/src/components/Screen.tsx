// 分頁的外框。長相跟 DomyScreen 一樣，多做兩件事：
// 1. 鍵盤出來時，正在打字的那一格會被推到鍵盤上面（DomyScreen 沒處理這個）。
// 2. 可以拿到捲動的把手，也知道現在捲到哪，操作說明要捲到某一塊時用。
import type { ComponentRef, ReactNode, RefObject } from 'react';
import { ScrollView } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { DomyText, T, useDomy } from '@domy/design';

export type Scroller = ComponentRef<typeof ScrollView>;

export function Screen({ title, bottomInset, scroller, scrollY, children }: { title: string; bottomInset: number; scroller?: RefObject<Scroller | null>; scrollY?: RefObject<number>; children: ReactNode }) {
  const { c } = useDomy();
  const insets = useSafeAreaInsets();
  return (
    <ScrollView
      ref={scroller}
      style={{ flex: 1, backgroundColor: c.canvas }}
      automaticallyAdjustKeyboardInsets
      keyboardShouldPersistTaps="handled"
      keyboardDismissMode="interactive"
      scrollEventThrottle={16}
      onScroll={scrollY ? (e) => void (scrollY.current = e.nativeEvent.contentOffset.y) : undefined}
      contentContainerStyle={{ paddingTop: insets.top + T.space[2], paddingBottom: bottomInset, paddingHorizontal: T.size.screenMargin, gap: T.space[6] }}
    >
      <DomyText variant="largeTitle" accessibilityRole="header">
        {title}
      </DomyText>
      {children}
    </ScrollView>
  );
}
