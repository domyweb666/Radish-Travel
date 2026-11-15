// 「行前」分頁：要做的（要先訂、檢查表）、須知、花費。出發前看的東西都在這裡。
// 每一條只留一行短的核對狀態；完整的來源收在「看每一條的來源」。
import { useState } from 'react';
import { DomyButton, DomyEmptyState, DomySection, DomyText, DomyTextField, useTabBarClearance } from '@domy/design';
import { TabTrip } from '../components/icons';
import { Screen } from '../components/Screen';
import { Sheet } from '../components/Sheet';
import { Banner, Card, CheckRow, Segmented, TextRow } from '../components/ui';
import { CHECKLIST, DIFF, DISHES, EATS, GIFTS, GIFT_RULES, PART, TABOO, TABOO_LEVEL, type Fact, type Pick } from '../data/seoul';
import { addDays, fmtDay } from '../domain/dates';
import { allItems, cost, costRange, money } from '../domain/plan';
import { useApp } from '../store';

type Tab = 'todo' | 'know' | 'eat' | 'cost';

/** 列上只放短的：二手核對・11/14，或是未核對 */
const factShort = (f: Fact) => {
  if (!f.checked) return '未核對';
  const [, m, d] = f.checked.split('-').map(Number);
  return `${f.status}・${m}/${d}`;
};
const factFull = (f: Fact) => (f.checked ? `${f.status} ${f.checked}・來源：${f.source}` : '還沒核對過，沒有來源');

function Sources({ title, facts, onClose }: { title: string; facts: Fact[]; onClose: () => void }) {
  return (
    <Sheet visible title={title} onClose={onClose}>
      <DomyText variant="subheadline" tone="secondary">
        「二手核對」是從旅遊媒體交叉對過，沒有直接讀官方頁。「來源較舊」是找到的資料比較舊，可能已經變了。「未核對」是還沒查。入境規定出發前請回官方頁再看一次。
      </DomyText>
      <DomySection>
        {facts.map((f) => (
          <TextRow key={f.text} title={f.text} note={factFull(f)} />
        ))}
      </DomySection>
    </Sheet>
  );
}

function Todo() {
  const { s, act, phase } = useApp();
  const [src, setSrc] = useState(false);
  const trip = s.trip;
  const toggle = (k: string) => act((d) => void (d.checks[k] = !d.checks[k]));
  const books = trip ? allItems(trip).filter((x) => x.it.b) : [];
  const done = CHECKLIST.filter((r) => s.checks[r.id]).length;
  const soon = phase?.kind === 'plan' && phase.daysToGo <= 7;
  const recheck = trip ? allItems(trip).filter((x) => x.it.b || /休館|班次|名額/.test(x.it.tip ?? '')) : [];
  return (
    <>
      {soon && recheck.length ? (
        <Banner text={`還有 ${phase.daysToGo} 天出發。這 ${recheck.length} 站有訂位、休館日或班次，再查一次：${recheck.map((x) => x.it.n).join('、')}。`} />
      ) : null}
      {trip && books.length ? (
        <DomySection title="這趟要先訂的" footer="訂好了就打勾。怎麼訂、外國人訂不訂得到，這一版還不知道，要自己查。">
          {books.map(({ it, s: sl }) => (
            <CheckRow
              key={it.id}
              checked={!!s.checks['b_' + it.id]}
              title={it.n}
              note={`第 ${sl.day} 天 ${fmtDay(addDays(trip.start, sl.day - 1))} ${PART[sl.part]}`}
              onPress={() => toggle('b_' + it.id)}
            />
          ))}
        </DomySection>
      ) : null}
      <DomySection title={`行前檢查表　${done}／${CHECKLIST.length}`}>
        {CHECKLIST.map((r) => (
          <CheckRow key={r.id} checked={!!s.checks[r.id]} title={r.text} note={factShort(r)} onPress={() => toggle(r.id)} />
        ))}
      </DomySection>
      <DomyButton title="看每一條的來源" variant="plain" fullWidth onPress={() => setSrc(true)} />
      {src ? <Sources title="檢查表的來源" facts={CHECKLIST} onClose={() => setSrc(false)} /> : null}
    </>
  );
}

function Know() {
  const [src, setSrc] = useState(false);
  return (
    <>
      {([3, 2, 1] as const).map((lv) => (
        <DomySection key={lv} title={TABOO_LEVEL[lv]}>
          {TABOO.filter((r) => r.level === lv).map((r) => (
            <TextRow key={r.text} title={r.text} note={r.result} />
          ))}
        </DomySection>
      ))}
      <DomySection title="跟台灣不一樣的地方">
        {DIFF.map((r) => (
          <TextRow key={r.text} title={r.text} note={r.checked ? undefined : '未核對'} />
        ))}
      </DomySection>
      <DomyButton title="看每一條的來源" variant="plain" fullWidth onPress={() => setSrc(true)} />
      {src ? <Sources title="須知的來源" facts={[...TABOO, ...DIFF]} onClose={() => setSrc(false)} /> : null}
    </>
  );
}

function PickList({ title, items, footer }: { title: string; items: Pick[]; footer?: string }) {
  return (
    <DomySection title={title} footer={footer}>
      {items.map((p) => (
        <TextRow key={p.n} title={p.kr ? `${p.n}　${p.kr}` : p.n} note={p.note} />
      ))}
    </DomySection>
  );
}

/** 吃與買：必吃、特色料理、伴手禮。全部還沒核對，畫面上要講清楚 */
function EatBuy() {
  return (
    <>
      <Banner text="這一頁是先整理的清單，還沒逐條核對，也還沒附來源。店家、價格、哪裡買，去之前自己查一下。" />
      <PickList title="到首爾多半會吃的" items={EATS} />
      <PickList title="比較特別、敢吃再試的" items={DISHES} />
      <PickList title="伴手禮" items={GIFTS} />
      <DomySection title="帶回台灣之前" footer="入境規定會改，出發前請看農業部動植物防疫檢疫署和財政部關務署的官方頁。">
        {GIFT_RULES.map((r) => (
          <TextRow key={r} title={r} note="未核對" />
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
          每人粗估{trip.flight ? '' : '（不含機票）'}
        </DomyText>
        <DomyText variant="title1">{costRange(trip, s.settings)}</DomyText>
      </Card>
      <DomySection footer="都是粗估，沒有核對過票價和匯率，只能看比例。購物不算在裡面。住宿和一天吃喝的預算在「我」改。">
        {c.rows.map((r) => (
          <TextRow key={r.name} title={r.name} note={r.note} right={<DomyText variant="headline">{money(r.amount)}</DomyText>} />
        ))}
      </DomySection>
      <DomyTextField
        label="機票（每人，NT$）"
        helper="自己填，會加進上面的粗估。"
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
    <Screen title="行前" bottomInset={clearance}>
      <Segmented<Tab>
        value={tab}
        onChange={setTab}
        options={[
          ['todo', '要做的'],
          ['know', '須知'],
          ['eat', '吃與買'],
          ['cost', '花費'],
        ]}
      />
      {tab === 'todo' ? <Todo /> : null}
      {tab === 'know' ? <Know /> : null}
      {tab === 'eat' ? <EatBuy /> : null}
      {tab === 'cost' ? (
        s.trip ? (
          <Cost />
        ) : (
          <DomyEmptyState icon={(color) => <TabTrip color={color} />} title="還沒有行程" body="排好一趟之後，這裡會有每人大概要花多少。" action={{ title: '去排一趟', onPress: goTrip }} />
        )
      ) : null}
    </Screen>
  );
}
