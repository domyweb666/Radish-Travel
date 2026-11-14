// 「這趟」分頁。沒有行程時是開一趟；出發前是整趟的總覽和每一天；旅途中最上面是下一站。
import * as Haptics from 'expo-haptics';
import { Pressable, Share, View } from 'react-native';
import { DomyButton, DomyScreen, DomySection, DomyStatGrid, DomyText, T, useDomy, useTabBarClearance } from '@domy/design';
import { CatIcon, kindName } from '../components/icons';
import { Radish, RadishField } from '../components/Radish';
import { Banner, Card, Tag, TagRow, TextRow } from '../components/ui';
import { PART, PULL_LINES } from '../data/seoul';
import { addDays, fmtDay } from '../domain/dates';
import {
  PARTS, allItems, areaOf, costRange, dayLegs, dayStops, generate, legText, nearbyPool, newId, planText, seedOut, slotAt, swapParts,
} from '../domain/plan';
import type { Slot, Stop, Trip } from '../domain/types';
import { useSheets } from '../sheets/host';
import { useApp } from '../store';
import { StartTrip } from './StartTrip';

function StopRow({ it, slot, leg, onPress }: { it: Stop; slot: Slot; leg: string; onPress: () => void }) {
  const { c } = useDomy();
  const pulled = it.status === 'pulled';
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${PART[slot.part]}，${it.n}，${it.why}`}
      onPress={onPress}
      style={({ pressed }) => ({
        paddingVertical: T.space[3],
        gap: T.space[2],
        marginHorizontal: -T.space[4],
        paddingHorizontal: T.space[4],
        backgroundColor: pressed ? c.surfaceMuted : 'transparent',
      })}
    >
      <DomyText variant="caption" tone="secondary">
        {leg}
      </DomyText>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
        <CatIcon it={it} />
        <View style={{ flex: 1, minWidth: 0, gap: T.space[1] / 2 }}>
          <DomyText variant="footnote" tone="secondary">
            {PART[slot.part]}・{areaOf(it)}
          </DomyText>
          <DomyText variant="headline" tone={pulled ? 'secondary' : 'primary'} style={pulled ? { textDecorationLine: 'line-through' } : null}>
            {it.n}
          </DomyText>
          {it.kr ? (
            <DomyText variant="footnote" tone="secondary">
              {it.kr}
            </DomyText>
          ) : null}
        </View>
        <Radish size={it.s} faded={pulled} />
      </View>
      <DomyText variant="subheadline" tone="strong">
        {it.why}
      </DomyText>
      {it.b || it.ai ? (
        <TagRow>
          {it.b ? <Tag label="要先訂" tone="accent" /> : null}
          {it.ai ? <Tag label="AI 加的・未核對" tone="warn" /> : null}
        </TagRow>
      ) : null}
    </Pressable>
  );
}

function DaySection({ trip, day, isToday }: { trip: Trip; day: number; isToday: boolean }) {
  const { s, act } = useApp();
  const sheets = useSheets();
  const slots = trip.slots.filter((x) => x.day === day);
  const stops = dayStops(trip, day);
  const legs = dayLegs(trip, s.settings, day);
  const pool = [...nearbyPool(trip, day)];
  const total = legs.reduce((n, l) => n + (l ? l.min : 0), 0);
  const canSwap = !!slotAt(trip, day, 'am') && !!slotAt(trip, day, 'pm');
  let i = 0;
  const rows: React.ReactNode[] = [];
  slots.forEach((sl) => {
    if (sl.off) {
      rows.push(<TextRow key={sl.part} title={`${PART[sl.part]}・在路上`} />);
      return;
    }
    sl.items.forEach((it) => {
      const idx = i++;
      rows.push(
        <StopRow
          key={it.id}
          it={it}
          slot={sl}
          leg={`${idx === 0 ? '從住的地方出發・' : ''}${legText(legs[idx])}`}
          onPress={() => sheets.open({ kind: 'stop', id: it.id })}
        />,
      );
    });
    if (!sl.items.length) rows.push(<TextRow key={sl.part} title={`${PART[sl.part]}・${sl.rest ? '留白' : '空的'}`} note={sl.rest ? '這段不排東西' : undefined} />);
  });
  if (pool.length) rows.push(<TextRow key="pool" title="順路可去" note={`不排時間：${pool.join('、')}`} />);
  return (
    <View style={{ gap: T.space[2] }}>
      <DomySection
        title={`第 ${day} 天　${fmtDay(addDays(trip.start, day - 1))}${isToday ? '　今天' : ''}`}
        footer={stops.length ? `${stops.length} 站・路上大約 ${total} 分鐘（估）` : undefined}
      >
        {rows}
      </DomySection>
      {stops.length ? (
        <View style={{ flexDirection: 'row', gap: T.space[2], paddingHorizontal: T.space[1] }}>
          <DomyButton title="看這天的地圖" variant="secondary" size="compact" onPress={() => sheets.open({ kind: 'map', day })} />
          {canSwap ? (
            <DomyButton
              title="上午下午對調"
              variant="secondary"
              size="compact"
              onPress={() => act((d) => (d.trip ? (swapParts(d.trip, day, 'am', 'pm') ?? `第 ${day} 天上午和下午對調了。`) : undefined), { undoable: true })}
            />
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

function NextStop({ trip, day }: { trip: Trip; day: number }) {
  const { act } = useApp();
  const sheets = useSheets();
  const left = dayStops(trip, day).filter((x) => x.it.status === 'kept');
  const allLeft = allItems(trip).filter((x) => x.it.status === 'kept').length;
  if (!left.length) {
    return (
      <Card>
        <DomyText variant="title2">{allLeft ? '今天的都拔完了' : '這趟的都拔完了'}</DomyText>
        <DomyText variant="body" tone="secondary">
          剩下的時間是你的。
        </DomyText>
      </Card>
    );
  }
  const { it, s: slot } = left[0];
  const big = left.find((x) => x.it.s === 'L');
  return (
    <Card>
      <DomyText variant="footnote" tone="secondary">
        下一站・{PART[slot.part]}・{areaOf(it)}・{kindName(it)}
      </DomyText>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
        <CatIcon it={it} />
        <View style={{ flex: 1, gap: T.space[1] / 2 }}>
          <DomyText variant="title2">{it.n}</DomyText>
          {it.kr ? (
            <DomyText variant="subheadline" tone="secondary">
              {it.kr}
            </DomyText>
          ) : null}
        </View>
        <Radish size={it.s} scale={1.4} />
      </View>
      {it.tip ? (
        <DomyText variant="subheadline" tone="secondary">
          {it.tip}。
        </DomyText>
      ) : null}
      <DomyButton
        title="去過了，拔起來"
        fullWidth
        haptic={false}
        onPress={() => {
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
          act(
            (d) => {
              const x = d.trip ? allItems(d.trip).find((y) => y.it.id === it.id) : undefined;
              if (x) x.it.status = 'pulled';
              return PULL_LINES[Math.floor(Math.random() * PULL_LINES.length)];
            },
            { undoable: true },
          );
        }}
      />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: T.space[2] }}>
        <DomyButton title="地圖與韓文" variant="secondary" size="compact" onPress={() => sheets.open({ kind: 'stop', id: it.id })} />
        {big ? (
          <DomyButton
            title="今天排輕一點"
            variant="secondary"
            size="compact"
            onPress={() =>
              act(
                (d) => {
                  if (!d.trip) return;
                  seedOut(d.trip, d.seeds, big.it.id, '那天想排輕一點');
                  return `今天的大站「${big.it.n}」先放到下次再來。`;
                },
                { undoable: true },
              )
            }
          />
        ) : null}
        <DomyButton
          title="這站不去"
          variant="secondary"
          size="compact"
          onPress={() =>
            act(
              (d) => {
                if (!d.trip) return;
                seedOut(d.trip, d.seeds, it.id, '旅途中說不去了');
                return `「${it.n}」放到下次再來了。`;
              },
              { undoable: true },
            )
          }
        />
      </View>
    </Card>
  );
}

export function TripScreen({ goSettings }: { goSettings: () => void }) {
  const { s, act, phase } = useApp();
  const sheets = useSheets();
  const clearance = useTabBarClearance();
  const trip = s.trip;
  if (!trip || !phase) return <StartTrip goSettings={goSettings} />;

  const all = allItems(trip);
  const big = all.filter((x) => x.it.s === 'L').length;
  const books = all.filter((x) => x.it.b).length;
  const rests = trip.slots.filter((x) => x.rest).length;
  const today = phase.kind === 'trip' ? phase.day : undefined;
  const end = addDays(trip.start, trip.days - 1);
  const days = Array.from({ length: trip.days }, (_, i) => i + 1);
  const ordered = today ? [...days.filter((d) => d >= today), ...days.filter((d) => d < today)] : days;
  const pulled = all.filter((x) => x.it.status === 'pulled');

  const archive = () =>
    act(
      (d) => {
        if (!d.trip) return;
        const items = allItems(d.trip)
          .filter((x) => x.it.status === 'pulled')
          .map(({ it }) => ({ n: it.n, s: it.s, c: it.c, ic: it.ic, say: it.say }));
        if (items.length) d.baskets.unshift({ id: newId('b'), title: `首爾 ${d.trip.days} 天・${fmtDay(d.trip.start)}出發`, items });
        d.trip = null;
        d.chat = [];
        d.debugDay = null;
        d.settingsDirty = false;
        return items.length ? `這一籃 ${items.length} 顆收進蘿蔔籃了。` : '這趟收起來了。';
      },
      { undoable: true },
    );

  const share = () => {
    const text = `首爾 ${trip.days} 天　${fmtDay(trip.start)}–${fmtDay(end)}\n\n${planText(trip, false, (d) => fmtDay(addDays(trip.start, d - 1)))}\n（蘿蔔旅行排的。地點還沒核對過，看完跟我說哪天想改。）`;
    Share.share({ message: text }).catch(() => {});
  };

  return (
    <DomyScreen title={phase.kind === 'trip' ? `第 ${phase.day} 天` : `首爾 ${trip.days} 天`} bottomInset={clearance}>
      <DomyText variant="subheadline" tone="secondary" style={{ marginTop: -T.space[4] }}>
        {fmtDay(trip.start)}–{fmtDay(end)}・{trip.people === 4 ? '三四個人' : `${trip.people} 個人`}
        {phase.kind === 'plan' ? `・還有 ${phase.daysToGo} 天出發` : phase.kind === 'trip' ? `・首爾 ${trip.days} 天` : '・已經回來了'}
      </DomyText>

      {phase.kind === 'done' ? (
        <Card>
          <DomyText variant="title2">這一籃收好了</DomyText>
          <DomyText variant="body" tone="secondary">
            這趟拔了 {pulled.length} 顆。回來一週內，挑一顆講給沒去的人聽。
          </DomyText>
          <DomyButton title="收進蘿蔔籃，開新的一趟" fullWidth onPress={archive} />
        </Card>
      ) : null}

      {today ? <NextStop trip={trip} day={today} /> : null}

      {s.settingsDirty ? (
        <Banner
          text="「我」裡的設定改過了，這趟還是照舊的排。"
          action={{
            title: '照新的設定重排',
            onPress: () =>
              act(
                (d) => {
                  if (!d.trip) return;
                  const { purpose, start, days: n, arrive, leave, people, flight } = d.trip;
                  d.trip = { ...generate({ purpose, start, days: n, arrive, leave, people }, d.settings), flight };
                  d.settingsDirty = false;
                  return '照新的設定重排了。手動改過的地方也一起重排了。';
                },
                { undoable: true },
              ),
          }}
        />
      ) : null}

      {phase.kind === 'plan' ? (
        <View style={{ gap: T.space[3] }}>
          <DomyStatGrid
            items={[
              { value: String(big), unit: '個', label: '大站' },
              { value: String(all.length - big), unit: '個', label: '小站' },
              { value: String(books), unit: '個', label: '要先訂' },
              { value: String(rests), unit: '段', label: '留白' },
            ]}
          />
          <DomyText variant="footnote" tone="secondary" style={{ paddingHorizontal: T.space[1] }}>
            每人粗估 {costRange(trip, s.settings)}
            {trip.flight ? '' : '（不含機票）'}。明細在「行前」。
          </DomyText>
        </View>
      ) : null}

      {phase.kind !== 'done' ? (
        <View style={{ gap: T.space[2] }}>
          <DomyButton title="用講的改行程" variant={today ? 'secondary' : 'primary'} fullWidth onPress={() => sheets.open({ kind: 'chat' })} />
          <View style={{ flexDirection: 'row', gap: T.space[2] }}>
            <DomyButton title="傳給旅伴看" variant="secondary" size="compact" onPress={share} />
            <DomyButton title="自己加一站" variant="secondary" size="compact" onPress={() => sheets.open({ kind: 'add' })} />
          </View>
        </View>
      ) : null}

      <Banner text="這一版的地點是範例資料，還沒接上地點查證。營業時間、休館日、票價都要自己查過。" />

      <Card>
        <RadishField trip={trip} today={today} />
      </Card>

      {ordered.map((d) => (
        <DaySection key={d} trip={trip} day={d} isToday={d === today} />
      ))}

      {s.pool.length ? (
        <DomySection title="你自己加的、順路有空再去">
          {s.pool.map((n, i) => (
            <TextRow key={i} title={n} />
          ))}
        </DomySection>
      ) : null}

      {phase.kind !== 'done' ? (
        <DomyButton title="這趟不排了，收起來" variant="plain" size="compact" style={{ alignSelf: 'center' }} onPress={archive} />
      ) : null}
    </DomyScreen>
  );
}
