// 「這趟」分頁。沒有行程時是開一趟；有行程時上面一排是每一天的分頁，一次只看一天。
// 旅途中最上面多一張「下一站」。不常用的動作收在「更多」。
import { useEffect, useRef, useState, type RefObject } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { DomyButton, DomySection, DomyText, T, useDomy, useTabBarClearance } from '@domy/design';
import { RadishBuddy } from '../components/buddy/RadishBuddy';
import { CatIcon } from '../components/icons';
import { PullMoment } from '../components/PullMoment';
import { Radish } from '../components/Radish';
import { Screen, type Scroller } from '../components/Screen';
import { Spotlight, type SpotTarget } from '../components/Spotlight';
import { Banner, Card, Tag, TagRow, TextRow } from '../components/ui';
import { HOTEL, PART, PULL_LINES } from '../data/seoul';
import { addDays, fmtDay } from '../domain/dates';
import { allItems, areaOf, baseOf, dayLegs, dayStops, draftOf, generate, seedOut } from '../domain/plan';
import { archiveTrip } from '../domain/tripActions';
import type { Size, Slot, Stop, Trip } from '../domain/types';
import { useSheets } from '../sheets/host';
import { useApp } from '../store';
import { StartTrip } from './StartTrip';

/** 每一天一個分頁，橫向排，天數多可以左右滑 */
function DayTabs({ trip, value, today, onChange }: { trip: Trip; value: number; today?: number; onChange: (d: number) => void }) {
  const { c } = useDomy();
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      accessibilityRole="tablist"
      style={{ marginHorizontal: -T.size.screenMargin }}
      contentContainerStyle={{ gap: T.space[2], paddingHorizontal: T.size.screenMargin }}
    >
      {Array.from({ length: trip.days }, (_, i) => i + 1).map((d) => {
        const on = d === value;
        return (
          <Pressable
            key={d}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            accessibilityLabel={`第 ${d} 天，${fmtDay(addDays(trip.start, d - 1))}${d === today ? '，今天' : ''}`}
            onPress={() => onChange(d)}
            style={{
              minHeight: T.size.row,
              paddingHorizontal: T.space[4],
              borderRadius: T.radius.lg,
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: on ? c.accent : c.surface,
            }}
          >
            <DomyText variant="callout" tone={on ? 'onAccent' : 'primary'}>
              {d === today ? '今天' : `第 ${d} 天`}
            </DomyText>
            <DomyText variant="caption" tone={on ? 'onAccent' : 'secondary'}>
              {fmtDay(addDays(trip.start, d - 1))}
            </DomyText>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

/** showRadish：旅途中才放蘿蔔，代表「這一站還沒拔」。出發前只是行程表，不放 */
function StopRow({ it, slot, onPress, showRadish }: { it: Stop; slot: Slot; onPress: () => void; showRadish: boolean }) {
  const { c } = useDomy();
  const pulled = it.status === 'pulled';
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${PART[slot.part]}，${it.n}，${it.why}`}
      onPress={onPress}
      style={({ pressed }) => ({
        paddingVertical: T.space[3],
        flexDirection: 'row',
        alignItems: 'center',
        gap: T.space[3],
        marginHorizontal: -T.space[4],
        paddingHorizontal: T.space[4],
        backgroundColor: pressed ? c.surfaceMuted : 'transparent',
      })}
    >
      <CatIcon it={it} />
      <View style={{ flex: 1, minWidth: 0, gap: T.space[1] / 2 }}>
        <DomyText variant="footnote" tone="secondary">
          {PART[slot.part]}・{areaOf(it)}
        </DomyText>
        <DomyText variant="headline" tone={pulled ? 'secondary' : 'primary'} style={pulled ? { textDecorationLine: 'line-through' } : null}>
          {it.n}
        </DomyText>
        <DomyText variant="subheadline" tone="strong">
          {it.why}
        </DomyText>
        {it.b || it.ai ? (
          <TagRow>
            {it.b ? <Tag label="要先訂" tone="accent" /> : null}
            {it.ai ? <Tag label="AI 加的・未核對" tone="warn" /> : null}
          </TagRow>
        ) : null}
      </View>
      {showRadish || pulled ? <Radish size={it.s} faded={pulled} /> : null}
    </Pressable>
  );
}

/** firstRef：掛在這天第一站上，操作說明要照亮它 */
function DayCard({ trip, day, inTrip, firstRef }: { trip: Trip; day: number; inTrip: boolean; firstRef: RefObject<SpotTarget | null> }) {
  const { s } = useApp();
  const sheets = useSheets();
  const slots = trip.slots.filter((x) => x.day === day);
  const stops = dayStops(trip, day);
  const total = dayLegs(trip, s.settings, day).reduce((n, l) => n + (l ? l.min : 0), 0);
  const off = slots.filter((x) => x.off).map((x) => PART[x.part]);
  const rows: React.ReactNode[] = [];
  if (off.length) rows.push(<TextRow key="off" title={`${off.join('、')}在路上`} note="這段時間不排東西" />);
  slots.forEach((sl) => {
    if (sl.off) return;
    sl.items.forEach((it) => {
      const row = <StopRow key={it.id} it={it} slot={sl} showRadish={inTrip} onPress={() => sheets.open({ kind: 'stop', id: it.id })} />;
      rows.push(
        it.id === stops[0]?.it.id ? (
          <View key={it.id} ref={firstRef} collapsable={false}>
            {row}
          </View>
        ) : (
          row
        ),
      );
    });
    if (!sl.items.length) rows.push(<TextRow key={sl.part} title={`${PART[sl.part]}・留白`} note="這段故意不排" />);
  });
  return (
    <View style={{ gap: T.space[3] }}>
      <DomySection footer={stops.length ? `${stops.length} 站・路上大約 ${total} 分鐘（估）。點一站看韓文名稱、花費、怎麼去，也可以移走或換掉。` : undefined}>{rows}</DomySection>
      {stops.length ? <DomyButton title="看這天的地圖" variant="secondary" fullWidth onPress={() => sheets.open({ kind: 'map', day })} /> : null}
    </View>
  );
}

function NextStop({ trip, day }: { trip: Trip; day: number }) {
  const { act } = useApp();
  const sheets = useSheets();
  // 剛拔起來的那一站。有值的時候整個畫面是拔蘿蔔的那一下
  const [pulled, setPulled] = useState<{ name: string; size: Size; line: string } | null>(null);
  const moment = pulled ? (
    <PullMoment
      name={pulled.name}
      size={pulled.size}
      line={pulled.line}
      onDone={() => setPulled(null)}
    />
  ) : null;
  const left = dayStops(trip, day).filter((x) => x.it.status === 'kept');
  if (!left.length) {
    return (
      <Card>
        {moment}
        <DomyText variant="title2">今天的都拔完了</DomyText>
        <DomyText variant="body" tone="secondary">
          剩下的時間是你的。
        </DomyText>
      </Card>
    );
  }
  const { it, s: slot } = left[0];
  return (
    <Card>
      {moment}
      <DomyText variant="footnote" tone="secondary">
        下一站・{PART[slot.part]}・{areaOf(it)}
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
          const line = PULL_LINES[Math.floor(Math.random() * PULL_LINES.length)];
          setPulled({ name: it.n, size: it.s, line });
          act(
            (d) => {
              const x = d.trip ? allItems(d.trip).find((y) => y.it.id === it.id) : undefined;
              if (x) x.it.status = 'pulled';
              return `「${it.n}」拔起來了。點那一站可以寫一句、加照片。`;
            },
            { undoable: true },
          );
        }}
      />
      <View style={{ flexDirection: 'row', gap: T.space[2] }}>
        <DomyButton title="地圖與韓文" variant="secondary" size="compact" onPress={() => sheets.open({ kind: 'stop', id: it.id })} />
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

/** 操作說明的三步，順序對應：第一站、用講的改行程、每天的分頁 */
const GUIDE = [
  '每一站都可以點。點進去有韓文名稱、大概花多少、怎麼去，也可以移到別的時段、換一個，或這次不去。',
  '想改行程，用講的就可以。例如「第二天輕鬆一點」。改了不滿意，按提示上的「復原」就回到原本的樣子。',
  '一次只看一天。要看別天，點上面這一排。',
];

export function TripScreen({ goSettings }: { goSettings: () => void }) {
  const { s, act, phase } = useApp();
  const sheets = useSheets();
  const clearance = useTabBarClearance();
  const trip = s.trip;
  const today = phase?.kind === 'trip' ? phase.day : undefined;
  const [day, setDay] = useState(today ?? 1);
  // 操作說明要用的：捲動的把手、現在捲到哪、要照亮的三塊
  const scroller = useRef<Scroller>(null);
  const scrollY = useRef(0);
  const firstStop = useRef<SpotTarget>(null);
  const talk = useRef<SpotTarget>(null);
  const tabs = useRef<SpotTarget>(null);
  useEffect(() => {
    if (today) setDay(today);
  }, [today]);
  if (!trip || !phase) return <StartTrip goSettings={goSettings} />;

  const shown = Math.min(day, trip.days);
  const end = addDays(trip.start, trip.days - 1);
  const pulled = allItems(trip).filter((x) => x.it.status === 'pulled').length;
  // 第一趟排好之後帶一次，只帶一次。回來之後的畫面沒有這三塊，不帶
  const guide = !s.guideSeen && phase.kind !== 'done';

  return (
    <Screen scroller={scroller} scrollY={scrollY} title={`首爾 ${trip.days} 天`} bottomInset={clearance}>
      <DomyText variant="subheadline" tone="secondary" style={{ marginTop: -T.space[4] }}>
        {fmtDay(trip.start)}–{fmtDay(end)}
        {phase.kind === 'plan' ? `・還有 ${phase.daysToGo} 天出發` : phase.kind === 'trip' ? `・今天是第 ${phase.day} 天` : '・已經回來了'}
        {`\n住${HOTEL[baseOf(trip, s.settings)].n}一帶${trip.stayName ? '・' + trip.stayName : ''}`}
      </DomyText>

      {phase.kind === 'done' ? (
        <Card>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
            <View style={{ flex: 1, gap: T.space[1] }}>
              <DomyText variant="title2">這趟走完了</DomyText>
              <DomyText variant="body" tone="secondary">
                這趟去了 {pulled} 個地方。有去過但沒按到的，點那一站可以補。在「旅行」可以把它做成地圖網頁，傳給沒去的人看。
              </DomyText>
            </View>
            <RadishBuddy action="bow" />
          </View>
          <DomyButton title="收起來，開新的一趟" fullWidth onPress={() => act((d) => archiveTrip(d), { undoable: true })} />
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
                  d.trip = { ...generate(draftOf(d.trip), d.settings), flight: d.trip.flight };
                  d.settingsDirty = false;
                  return '照新的設定重排了。手動改過的地方也一起重排了。';
                },
                { undoable: true },
              ),
          }}
        />
      ) : null}

      <View style={{ gap: T.space[3] }}>
        <View ref={tabs} collapsable={false}>
          <DayTabs trip={trip} value={shown} today={today} onChange={setDay} />
        </View>
        <DayCard trip={trip} day={shown} inTrip={phase.kind === 'trip'} firstRef={firstStop} />
      </View>

      {phase.kind !== 'done' ? (
        <View style={{ gap: T.space[2] }}>
          <View ref={talk} collapsable={false}>
            <DomyButton title="用講的改行程" variant={today ? 'secondary' : 'primary'} fullWidth onPress={() => sheets.open({ kind: 'chat' })} />
          </View>
          <DomyButton title="更多" variant="plain" fullWidth onPress={() => sheets.open({ kind: 'more', day: shown })} />
        </View>
      ) : null}

      <DomyText variant="footnote" tone="secondary" style={{ textAlign: 'center' }}>
        這一版的地點是範例資料，還沒核對過。營業時間、休館日、票價要自己查。
      </DomyText>

      {guide ? (
        <Spotlight
          steps={GUIDE.map((text, i) => ({ target: [firstStop, talk, tabs][i], text }))}
          scroller={scroller}
          scrollY={scrollY}
          onDone={() => {
            act((d) => void (d.guideSeen = true));
            scroller.current?.scrollTo({ y: 0, animated: true });
          }}
        />
      ) : null}
    </Screen>
  );
}
