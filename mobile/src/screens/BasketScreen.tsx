// 「蘿蔔籃」分頁：去過的（一趟一籃）和下次再來。
import { useState } from 'react';
import { View } from 'react-native';
import { DomyButton, DomyEmptyState, DomyScreen, DomySection, DomyText, T, useTabBarClearance } from '@domy/design';
import { CatIcon, IconSprout, TabBasket } from '../components/icons';
import { Radish } from '../components/Radish';
import { Segmented } from '../components/ui';
import { allItems, restoreSeed } from '../domain/plan';
import type { BasketItem } from '../domain/types';
import { useSheets } from '../sheets/host';
import { useApp } from '../store';

type Tab = 'been' | 'later';

function BeenRow({ it, onPress }: { it: BasketItem; onPress?: () => void }) {
  return (
    <View style={{ minHeight: T.size.row, paddingVertical: T.space[3], flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
      <CatIcon it={it} />
      <View style={{ flex: 1, gap: T.space[1] }}>
        <DomyText variant="body">{it.n}</DomyText>
        {it.say ? (
          <DomyText variant="subheadline" tone="secondary">
            「{it.say}」
          </DomyText>
        ) : onPress ? (
          <DomyButton title="寫一句" variant="plain" size="compact" style={{ alignSelf: 'flex-start', paddingHorizontal: 0 }} onPress={onPress} />
        ) : null}
      </View>
      <Radish size={it.s} />
    </View>
  );
}

export function BasketScreen({ goTrip }: { goTrip: () => void }) {
  const { s, act } = useApp();
  const sheets = useSheets();
  const clearance = useTabBarClearance();
  const [tab, setTab] = useState<Tab>('been');
  const cur = s.trip ? allItems(s.trip).filter((x) => x.it.status === 'pulled').map((x) => x.it) : [];
  return (
    <DomyScreen title="蘿蔔籃" bottomInset={clearance}>
      <Segmented<Tab>
        value={tab}
        onChange={setTab}
        options={[
          ['been', '去過的'],
          ['later', '下次再來'],
        ]}
      />
      {tab === 'been' ? (
        cur.length || s.baskets.length ? (
          <>
            {cur.length ? (
              <DomySection title="這一趟（首爾）" footer={`${cur.length} 顆`}>
                {cur.map((it) => (
                  <BeenRow key={it.id} it={it} onPress={() => sheets.open({ kind: 'stop', id: it.id })} />
                ))}
              </DomySection>
            ) : null}
            {s.baskets.map((b) => (
              <DomySection key={b.id} title={b.title} footer={`${b.items.length} 顆`}>
                {b.items.map((it, i) => (
                  <BeenRow key={i} it={it} />
                ))}
              </DomySection>
            ))}
          </>
        ) : (
          <DomyEmptyState
            icon={(color) => <TabBasket color={color} />}
            title="還沒有拔過蘿蔔"
            body="旅途中每去過一站，按「去過了，拔起來」，它就收在這裡，連同你寫的那一句。一趟旅行一籃。"
            action={s.trip ? undefined : { title: '去排一趟', onPress: goTrip }}
          />
        )
      ) : s.seeds.length ? (
        <DomySection footer="這趟排不進去、或你說先不要的站都在這裡，不會不見。">
          {s.seeds.map((seed) => (
            <View key={seed.id} style={{ minHeight: T.size.row, paddingVertical: T.space[3], flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
              <View style={{ flex: 1, gap: T.space[1] }}>
                <DomyText variant="body">{seed.n}</DomyText>
                <DomyText variant="footnote" tone="secondary">
                  {seed.a}・{seed.why}
                </DomyText>
              </View>
              {s.trip ? (
                <DomyButton
                  title="排回這趟"
                  variant="secondary"
                  size="compact"
                  onPress={() => act((d) => (d.trip ? restoreSeed(d.trip, d.seeds, seed.id) : undefined), { undoable: true })}
                />
              ) : null}
            </View>
          ))}
        </DomySection>
      ) : (
        <DomyEmptyState icon={(color) => <IconSprout color={color} />} title="這裡現在是空的" body="這趟拿掉的、排不進去的站會放在這裡，之後可以排回來。" />
      )}
    </DomyScreen>
  );
}
