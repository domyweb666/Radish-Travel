// 「行前」分頁：要先訂的、檢查表、須知、花費。出發前看的東西都在這裡。
import { useState } from 'react';
import { View } from 'react-native';
import { DomyEmptyState, DomyScreen, DomySection, DomyText, DomyTextField, T, useDomy, useTabBarClearance } from '@domy/design';
import { TabTrip } from '../components/icons';
import { Banner, Card, CheckRow, Segmented, TextRow } from '../components/ui';
import { CHECKLIST, DIFF, PART, TABOO, TABOO_LEVEL, type Fact } from '../data/seoul';
import { addDays, fmtDay } from '../domain/dates';
import { allItems, cost, costRange, money } from '../domain/plan';
import { useApp } from '../store';

type Tab = 'todo' | 'know' | 'cost';

const factNote = (f: Fact) => `${f.status}${f.checked ? ' ' + f.checked : ''}・來源：${f.source}`;

function Todo() {
  const { s, act, phase } = useApp();
  const { c } = useDomy();
  const trip = s.trip;
  const toggle = (k: string) => act((d) => void (d.checks[k] = !d.checks[k]));
  const books = trip ? allItems(trip).filter((x) => x.it.b) : [];
  const done = CHECKLIST.filter((r) => s.checks[r.id]).length;
  const soon = phase?.kind === 'plan' && phase.daysToGo <= 7;
  const recheck = trip ? allItems(trip).filter((x) => x.it.b || /休館|班次|名額/.test(x.it.tip ?? '')) : [];
  return (
    <>
      {soon && recheck.length ? (
        <Banner text={`還有 ${phase.daysToGo} 天出發。這 ${recheck.length} 站有訂位、休館日或班次，再查一次：${recheck.map((x) => x.it.n).join('、')}。入境規定也回官方頁看一眼。`} />
      ) : null}
      {trip ? (
        books.length ? (
          <DomySection title="這趟要先訂的" footer="訂好了就打勾。這一版還不知道每一間怎麼訂、外國人訂不訂得到，要自己查。">
            {books.map(({ it, s: sl }) => (
              <CheckRow
                key={it.id}
                checked={!!s.checks['b_' + it.id]}
                title={it.n}
                note={`第 ${sl.day} 天 ${fmtDay(addDays(trip.start, sl.day - 1))} ${PART[sl.part]}${it.tip ? '・' + it.tip : ''}`}
                onPress={() => toggle('b_' + it.id)}
              />
            ))}
          </DomySection>
        ) : (
          <Card>
            <DomyText variant="subheadline" tone="secondary">
              這趟沒有要先訂的站。
            </DomyText>
          </Card>
        )
      ) : null}
      <View style={{ gap: T.space[2] }}>
        <DomySection title="行前檢查表" footer="入境規定出發前一週回官方頁再看一次。">
          <View style={{ paddingVertical: T.space[3], gap: T.space[2] }}>
            <DomyText variant="headline">
              {done}／{CHECKLIST.length} 項好了
            </DomyText>
            <View style={{ height: T.space[2], borderRadius: T.radius.pill, backgroundColor: c.surfaceMuted, overflow: 'hidden' }}>
              <View style={{ width: `${(done / CHECKLIST.length) * 100}%`, height: '100%', backgroundColor: c.accent }} />
            </View>
          </View>
          {CHECKLIST.map((r) => (
            <CheckRow key={r.id} checked={!!s.checks[r.id]} title={r.text} note={factNote(r)} onPress={() => toggle(r.id)} />
          ))}
        </DomySection>
      </View>
    </>
  );
}

function Know() {
  return (
    <>
      {([3, 2, 1] as const).map((lv) => (
        <DomySection key={lv} title={TABOO_LEVEL[lv]}>
          {TABOO.filter((r) => r.level === lv).map((r) => (
            <TextRow key={r.text} title={r.text} note={`${r.result}\n${factNote(r)}`} />
          ))}
        </DomySection>
      ))}
      <DomySection title="跟台灣不一樣的地方" footer="標「二手核對」的，是從旅遊媒體交叉對過，沒有直接讀官方頁。標「未核對」的還沒查。">
        {DIFF.map((r) => (
          <TextRow key={r.text} title={r.text} note={factNote(r)} />
        ))}
      </DomySection>
    </>
  );
}

function Cost() {
  const { s, act } = useApp();
  const trip = s.trip;
  if (!trip) return null;
  const c = cost(trip, s.settings);
  return (
    <>
      <Card>
        <DomyText variant="footnote" tone="secondary">
          每人粗估
        </DomyText>
        <DomyText variant="title1">{costRange(trip, s.settings)}</DomyText>
        {c.people > 1 ? (
          <DomyText variant="subheadline" tone="secondary">
            {c.people === 4 ? '三四個人' : `${c.people} 個人`}合計大約 {money(c.total * c.people)}
          </DomyText>
        ) : null}
      </Card>
      <DomySection footer="這些數字是粗估，沒有核對過票價和匯率，只能看比例。購物不算在裡面。住宿等級和一天吃喝的預算在「我」改。">
        {c.rows.map((r) => (
          <TextRow key={r.name} title={r.name} note={r.note} right={<DomyText variant="headline">{money(r.amount)}</DomyText>} />
        ))}
        <TextRow title="合計（每人）" right={<DomyText variant="title3">{money(c.total)}</DomyText>} />
      </DomySection>
      <DomyTextField
        label="機票（每人，NT$）"
        helper="自己填，會加進合計。"
        keyboardType="number-pad"
        placeholder="例如 12000"
        maxLength={6}
        defaultValue={trip.flight ? String(trip.flight) : ''}
        onEndEditing={(e) => {
          const n = Math.min(200000, Math.max(0, parseInt(e.nativeEvent.text.replace(/\D/g, ''), 10) || 0));
          act((d) => {
            if (d.trip) d.trip.flight = n;
          });
        }}
      />
    </>
  );
}

export function PrepScreen({ goTrip }: { goTrip: () => void }) {
  const { s } = useApp();
  const clearance = useTabBarClearance();
  const [tab, setTab] = useState<Tab>('todo');
  return (
    <DomyScreen title="行前" bottomInset={clearance}>
      <Segmented<Tab>
        value={tab}
        onChange={setTab}
        options={[
          ['todo', '要做的'],
          ['know', '須知'],
          ['cost', '花費'],
        ]}
      />
      {tab === 'todo' ? <Todo /> : null}
      {tab === 'know' ? <Know /> : null}
      {tab === 'cost' ? (
        s.trip ? (
          <Cost />
        ) : (
          <DomyEmptyState icon={(color) => <TabTrip color={color} />} title="還沒有行程" body="排好一趟之後，這裡會有每人大概要花多少。" action={{ title: '去排一趟', onPress: goTrip }} />
        )
      ) : null}
    </DomyScreen>
  );
}
