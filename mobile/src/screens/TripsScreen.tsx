// 「旅行」分頁：每一趟是一個資料夾。
// 上面是現在打開的這一趟，接著是其他排好還沒去的、已經去過的；可以同時排好幾趟，點一下就切過去。
// 「下次再來」是這幾趟拿掉、排不進去的地方。
import { useState } from 'react';
import { Image, Pressable, View } from 'react-native';
import { DomyButton, DomyEmptyState, DomyListRow, DomyScreen, DomySection, DomyText, T, useDomy, useTabBarClearance } from '@domy/design';
import { IconSprout, TabTrips } from '../components/icons';
import { Segmented } from '../components/ui';
import { addDays, fmtDay, phaseOf } from '../domain/dates';
import { allItems, restoreSeed } from '../domain/plan';
import { openShelved, shelveCurrent, tripTitle } from '../domain/tripActions';
import type { Trip } from '../domain/types';
import { useSheets } from '../sheets/host';
import { photoUri } from '../io/photos';
import { useApp } from '../store';

type Tab = 'trips' | 'later';

/** 一趟一列：有封面照就放在右邊 */
function TripRow({ title, meta, cover, onPress }: { title: string; meta: string; cover?: string; onPress: () => void }) {
  const { c } = useDomy();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${title}，${meta}`}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: T.size.row,
        paddingVertical: T.space[3],
        marginHorizontal: -T.space[4],
        paddingHorizontal: T.space[4],
        flexDirection: 'row',
        alignItems: 'center',
        gap: T.space[3],
        backgroundColor: pressed ? c.surfaceMuted : 'transparent',
      })}
    >
      <View style={{ flex: 1, gap: T.space[1] }}>
        <DomyText variant="footnote" tone="secondary">
          {meta}
        </DomyText>
        <DomyText variant="headline" numberOfLines={2}>
          {title}
        </DomyText>
      </View>
      {cover ? <Image source={{ uri: photoUri(cover) }} accessibilityIgnoresInvertColors style={{ width: T.size.heroButton, height: T.size.row, borderRadius: T.radius.md }} /> : null}
    </Pressable>
  );
}

export function TripsScreen({ goTrip }: { goTrip: () => void }) {
  const { s, act, today, phase } = useApp();
  const sheets = useSheets();
  const clearance = useTabBarClearance();
  const [tab, setTab] = useState<Tab>('trips');
  const cur = s.trip;
  const curPulled = cur ? allItems(cur).filter((x) => x.it.status === 'pulled').length : 0;
  const range = (t: Pick<Trip, 'start' | 'days'>) => `${fmtDay(t.start)}–${fmtDay(addDays(t.start, t.days - 1))}`;
  const when = (t: Trip, debugDay: number | null) => {
    const p = phaseOf(t.start, t.days, today, debugDay);
    return p.kind === 'plan' ? `還有 ${p.daysToGo} 天出發` : p.kind === 'trip' ? `旅途中，第 ${p.day} 天` : '已經回來了';
  };
  const empty = !cur && !s.shelf.length && !s.baskets.length;

  return (
    <DomyScreen title="旅行" bottomInset={clearance}>
      <Segmented<Tab>
        value={tab}
        onChange={setTab}
        options={[
          ['trips', '我的旅行'],
          ['later', '下次再來'],
        ]}
      />
      {tab === 'trips' ? (
        empty ? (
          <DomyEmptyState icon={(color) => <TabTrips color={color} />} title="還沒有旅行" body="每排一趟，這裡就多一個資料夾。去過的地方、寫的那一句、照片都收在那一趟裡面。" action={{ title: '去排一趟', onPress: goTrip }} />
        ) : (
          <>
            {cur ? (
              <DomySection title="現在這趟" footer={phase?.kind === 'plan' ? undefined : '旅途中去過的站會收在這一趟裡，可以寫一句、加照片。'}>
                <TripRow meta={`${range(cur)}・${when(cur, s.debugDay)}`} title={tripTitle(cur)} cover={cur.cover} onPress={goTrip} />
                {curPulled ? <DomyListRow meta="這趟到目前為止" title={`去過的 ${curPulled} 站`} onPress={() => sheets.open({ kind: 'album', source: { from: 'current' } })} /> : null}
              </DomySection>
            ) : null}

            {s.shelf.length ? (
              <DomySection title="其他排好的" footer="點一下切到那一趟。現在這趟會原樣留著，不會不見。">
                {s.shelf.map((x) => (
                  <TripRow
                    key={x.id}
                    meta={`${range(x.trip)}・${when(x.trip, x.debugDay)}`}
                    title={tripTitle(x.trip)}
                    cover={x.trip.cover}
                    onPress={() => {
                      act((d) => openShelved(d, x.id));
                      goTrip();
                    }}
                  />
                ))}
              </DomySection>
            ) : null}

            <DomyButton
              title="開新的一趟"
              variant={cur ? 'secondary' : 'primary'}
              fullWidth
              onPress={() => {
                if (cur) act((d) => shelveCurrent(d));
                goTrip();
              }}
            />
            {cur ? (
              <DomyText variant="footnote" tone="secondary" style={{ textAlign: 'center' }}>
                現在這趟會留在「其他排好的」，隨時可以切回來。
              </DomyText>
            ) : null}

            {s.baskets.length ? (
              <DomySection title="去過的旅行">
                {s.baskets.map((b) => (
                  <TripRow
                    key={b.id}
                    meta={`${b.start && b.days ? range({ start: b.start, days: b.days }) + '・' : ''}去了 ${b.items.length} 個地方`}
                    title={b.title}
                    cover={b.cover}
                    onPress={() => sheets.open({ kind: 'album', source: { from: 'basket', id: b.id } })}
                  />
                ))}
              </DomySection>
            ) : null}
          </>
        )
      ) : s.seeds.length ? (
        <DomySection footer="排不進去、或你說先不要的地方都在這裡，不會不見。">
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
        <DomyEmptyState icon={(color) => <IconSprout color={color} />} title="這裡現在是空的" body="拿掉的、排不進去的地方會放在這裡，之後可以排回來。" />
      )}
    </DomyScreen>
  );
}
