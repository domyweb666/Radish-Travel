// 「行前」分頁：照旅遊的時間線排，出發前 → 在當地 → 回程，最後一格是花費。
// 打開時停在哪一段，看這趟走到哪：還沒出發是「出發前」，旅途中是「在當地」，最後一天和回來之後是「回程」。
// 每一條只留一行短的核對狀態；完整的來源收在「看每一條的來源」。
import { useState } from 'react';
import { Pressable, View } from 'react-native';
import { DomyButton, DomyEmptyState, DomySection, DomyText, DomyTextField, T, useDomy, useTabBarClearance } from '@domy/design';
import { TabTrip } from '../components/icons';
import { Screen } from '../components/Screen';
import { Sheet } from '../components/Sheet';
import { AllergyCard } from '../components/AllergyCard';
import { Banner, Card, CheckRow, Segmented, TextRow } from '../components/ui';
import { CHECKLIST, DIFF, DISHES, EATS, GIFTS, GIFT_RULES, NO_BRING, PART, SOS, TABOO, TABOO_LEVEL, type Fact, type Pick } from '../data/seoul';
import { addDays, fmtDay, type Phase } from '../domain/dates';
import { allItems, cost, costRange, money } from '../domain/plan';
import { remindOn, unbookedOf } from '../domain/remind';
import { addSpend, krwText, parseKrw, parseRate, removeSpend, spendTotal, toTwd } from '../domain/spend';
import { askReminders } from '../io/reminders';
import { useApp } from '../store';

export type PrepStage = 'before' | 'there' | 'back' | 'cost';

/** 這趟走到哪，就先開哪一段 */
const stageOf = (phase: Phase | null, days: number): PrepStage => {
  if (!phase || phase.kind === 'plan') return 'before';
  if (phase.kind === 'done') return 'back';
  return phase.day >= days ? 'back' : 'there';
};

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

/** 每一段最下面那顆「看每一條的來源」 */
function SourcesButton({ title, facts }: { title: string; facts: Fact[] }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <DomyButton title="看每一條的來源" variant="plain" fullWidth onPress={() => setOpen(true)} />
      {open ? <Sources title={title} facts={facts} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function FactList({ title, facts, footer }: { title: string; facts: Fact[]; footer?: string }) {
  return (
    <DomySection title={title} footer={footer}>
      {facts.map((r) => (
        <TextRow key={r.text} title={r.text} note={factShort(r)} />
      ))}
    </DomySection>
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

/** 出發前：要先訂的、要辦的事、行李要帶的、不能帶進韓國的 */
function Before() {
  const { s, act, phase, say, today } = useApp();
  const trip = s.trip;
  // 提醒：還有沒訂的、而且還來得及提醒，才給這顆按鈕
  const left = trip ? unbookedOf(trip, s.checks).length : 0;
  const on = trip ? remindOn(trip.start, today) : null;
  const toggle = (k: string) => act((d) => void (d.checks[k] = !d.checks[k]));
  const books = trip ? allItems(trip).filter((x) => x.it.b) : [];
  const soon = phase?.kind === 'plan' && phase.daysToGo <= 7;
  const recheck = trip ? allItems(trip).filter((x) => x.it.b || /休館|班次|名額/.test(x.it.tip ?? '')) : [];
  const checklist = (title: string, group: 'todo' | 'pack') => {
    const rows = CHECKLIST.filter((r) => r.group === group);
    return (
      <DomySection title={`${title}　${rows.filter((r) => s.checks[r.id]).length}／${rows.length}`}>
        {rows.map((r) => (
          <CheckRow key={r.id} checked={!!s.checks[r.id]} title={r.text} note={factShort(r)} onPress={() => toggle(r.id)} />
        ))}
      </DomySection>
    );
  };
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
      {on && left ? (
        s.remind ? (
          <>
            <DomyText variant="footnote" tone="secondary">
              {fmtDay(on)}早上 9 點會通知你還有哪幾站沒訂。在那之前全部勾完就不通知。
            </DomyText>
            <DomyButton title="不用提醒了" variant="plain" fullWidth onPress={() => act((d) => void (d.remind = false))} />
          </>
        ) : (
          <DomyButton
            title={`${fmtDay(on)}提醒我還沒訂的`}
            variant="secondary"
            fullWidth
            onPress={async () => {
              const r = await askReminders();
              if (r === 'ok') act((d) => ((d.remind = true), `好，${fmtDay(on)}早上 9 點提醒你。`));
              else say(r === 'denied' ? '通知沒有開。到 iPhone 的「設定」打開蘿蔔旅行的通知，再回來按一次。' : '網頁版沒有通知，要在手機上用。');
            }}
          />
        )
      ) : null}
      {checklist('要辦的事', 'todo')}
      {checklist('行李要帶的', 'pack')}
      <FactList title="不能帶進韓國的" facts={NO_BRING} footer="規定會改。出發前到韓國檢疫機關的官方頁再看一次。" />
      <SourcesButton title="出發前這一段的來源" facts={[...CHECKLIST, ...NO_BRING]} />
    </>
  );
}

/** 在當地：跟台灣不一樣的、當地人的地雷、吃什麼、出事打哪裡 */
function There() {
  const { s } = useApp();
  const allergy = s.settings.allergy;
  return (
    <>
      {allergy.length ? (
        <DomySection title={`你有過敏：${allergy.join('、')}`} footer="我不知道每家店用了哪些食材，沒辦法幫你排除。點餐前拿給店員看，自己確認。">
          <AllergyCard list={allergy} />
        </DomySection>
      ) : null}
      <FactList title="跟台灣不一樣的地方" facts={DIFF} />
      {([3, 2, 1] as const).map((lv) => (
        <DomySection key={lv} title={`當地人的地雷：${TABOO_LEVEL[lv]}`}>
          {TABOO.filter((r) => r.level === lv).map((r) => (
            <TextRow key={r.text} title={r.text} note={r.result} />
          ))}
        </DomySection>
      ))}
      <PickList title="到首爾多半會吃的" items={EATS} />
      <PickList title="比較特別、敢吃再試的" items={DISHES} footer="吃的這兩段是先整理的清單，還沒逐條核對，也沒有附來源。店家和價格去之前自己查。" />
      <FactList title="出事的時候打這些電話" facts={SOS} />
      <SourcesButton title="在當地這一段的來源" facts={[...DIFF, ...TABOO, ...SOS]} />
    </>
  );
}

/** 回程：買什麼回去、哪些不能帶、行李怎麼裝。全部還沒核對，畫面上要講清楚 */
function Back() {
  return (
    <>
      <Banner text="這一段是先整理的清單，還沒逐條核對，也還沒附來源。哪裡買、多少錢、能不能帶，買之前自己查一下。" />
      <PickList title="伴手禮" items={GIFTS} />
      <DomySection title="裝行李箱之前" footer="入境規定會改，回程前請看農業部動植物防疫檢疫署和財政部關務署的官方頁。">
        {GIFT_RULES.map((r) => (
          <TextRow key={r} title={r} note="未核對" />
        ))}
      </DomySection>
    </>
  );
}

function Cost() {
  const { s, act, phase } = useApp();
  const trip = s.trip;
  if (!trip) return null;
  const c = cost(trip, s.settings);
  // 出發之後常用的是記帳，放最上面；出發前先看粗估
  const gone = phase ? phase.kind !== 'plan' : false;
  return (
    <>
      {gone ? <Spent /> : null}
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
      {gone ? null : <Spent />}
    </>
  );
}

/** 對照表列的幾個金額（韓元），看一眼就知道大概多少台幣 */
const QUICK_KRW = [1000, 5000, 10000, 50000]; // domy-ignore: 是韓元金額，不是版面數值

/** 換算＋實際花的：一筆一筆記韓元，用自己填的匯率換台幣。跟上面的粗估分開，不混在一起算 */
function Spent() {
  const { s, act, phase } = useApp();
  const { c } = useDomy();
  // 記完一筆要把兩格清空：換一個 key 讓輸入框重來
  const [round, setRound] = useState(0);
  const [krw, setKrw] = useState('');
  const [note, setNote] = useState('');
  const trip = s.trip;
  if (!trip) return null;
  const list = trip.spend ?? [];
  const sum = spendTotal(trip);
  const day = phase?.kind === 'trip' ? phase.day : undefined;
  const twdOf = (n: number) => {
    const t = toTwd(n, trip.rate);
    return t == null ? null : `約 ${money(t)}`;
  };
  const typed = parseKrw(krw);
  const records = (
      <DomySection
        title="實際花的"
        footer={
          list.length
            ? `${sum.count} 筆，一共 ${krwText(sum.krw)}${sum.twd == null ? '。填了上面的匯率才會換成台幣' : `，${twdOf(sum.krw)}（照你填的匯率算）`}。點一筆可以刪掉，刪錯了按「復原」。`
            : '在當地花了錢就記一筆，存在手機裡，沒網路也能記。'
        }
      >
        {list.length ? (
          list.map((x) => (
            <Pressable
              key={x.id}
              accessibilityRole="button"
              accessibilityLabel={`${x.note ?? '沒寫花在哪'}，${krwText(x.krw)}，點一下刪掉`}
              onPress={() =>
                act(
                  (d) => {
                    const gone = d.trip ? removeSpend(d.trip, x.id) : undefined;
                    return gone ? `刪掉「${gone.note ?? krwText(gone.krw)}」這一筆了。` : undefined;
                  },
                  { undoable: true },
                )
              }
              style={({ pressed }) => ({ marginHorizontal: -T.space[4], paddingHorizontal: T.space[4], backgroundColor: pressed ? c.surfaceMuted : 'transparent' })}
            >
              <TextRow
                title={x.note ?? '沒寫花在哪'}
                note={x.day ? `第 ${x.day} 天` : undefined}
                right={
                  <View style={{ alignItems: 'flex-end' }}>
                    <DomyText variant="headline">{krwText(x.krw)}</DomyText>
                    {twdOf(x.krw) ? (
                      <DomyText variant="footnote" tone="secondary">
                        {twdOf(x.krw)}
                      </DomyText>
                    ) : null}
                  </View>
                }
              />
            </Pressable>
          ))
        ) : (
          <TextRow title="還沒有記" />
        )}
      </DomySection>
  );
  // 最上面那一格同時是換算器：邊打邊換。真的花了再按「記一筆」
  return (
    <>
      <DomyTextField
        key={`k${round}`}
        label="多少韓元"
        helper={typed ? (twdOf(typed) ? undefined : '在下面填匯率，這裡就會換成台幣。') : '打金額就換算成台幣。真的花了再按「記一筆」。'}
        keyboardType="number-pad"
        placeholder="例如 12000"
        maxLength={9}
        onChangeText={setKrw}
      />
      {typed && twdOf(typed) ? (
        <Card>
          <DomyText variant="title1" accessibilityLiveRegion="polite">
            {twdOf(typed)}
          </DomyText>
          <DomyText variant="footnote" tone="secondary">
            {krwText(typed)}，照你填的匯率算
          </DomyText>
        </Card>
      ) : null}
      <DomyTextField key={`n${round}`} label="花在哪（可以不填）" placeholder="例如：廣藏市場綠豆煎餅" maxLength={30} onChangeText={setNote} />
      <DomyButton
        title="記一筆"
        fullWidth
        disabled={!parseKrw(krw)}
        onPress={() => {
          act(
            (d) => {
              const x = d.trip ? addSpend(d.trip, parseKrw(krw), note, day) : undefined;
              return x ? `記了 ${krwText(x.krw)}。` : undefined;
            },
            { undoable: true },
          );
          setKrw('');
          setNote('');
          setRound((n) => n + 1);
        }}
      />
      <DomyTextField
        label="1000 韓元換多少台幣"
        helper="自己填，照你實際換到的匯率。這個 app 不會去抓匯率。"
        keyboardType="decimal-pad"
        placeholder="例如 23"
        maxLength={6}
        defaultValue={trip.rate ? String(trip.rate) : ''}
        onChangeText={(text) => {
          const r = parseRate(text);
          act((d) => {
            if (d.trip) d.trip.rate = r;
          });
        }}
      />
      {trip.rate ? (
        <DomySection title="對照表" footer="照你填的匯率算，四捨五入到元。">
          {QUICK_KRW.map((n) => (
            <TextRow key={n} title={krwText(n)} right={<DomyText variant="headline">{twdOf(n)}</DomyText>} />
          ))}
        </DomySection>
      ) : null}
      {records}
    </>
  );
}

/** open：從別頁跳過來時指定要開哪一段。沒指定就照這趟走到哪 */
export function PrepScreen({ goTrip, open }: { goTrip: () => void; open?: PrepStage }) {
  const { s, phase } = useApp();
  const clearance = useTabBarClearance();
  const [stage, setStage] = useState<PrepStage>(open ?? stageOf(phase, s.trip?.days ?? 0));
  return (
    <Screen title="行前" bottomInset={clearance}>
      <Segmented<PrepStage>
        value={stage}
        onChange={setStage}
        options={[
          ['before', '出發前'],
          ['there', '在當地'],
          ['back', '回程'],
          ['cost', '花費'],
        ]}
      />
      {stage === 'before' ? <Before /> : null}
      {stage === 'there' ? <There /> : null}
      {stage === 'back' ? <Back /> : null}
      {stage === 'cost' ? (
        s.trip ? (
          <Cost />
        ) : (
          <DomyEmptyState icon={(color) => <TabTrip color={color} />} title="還沒有行程" body="排好一趟之後，這裡會有每人大概要花多少。" action={{ title: '去排一趟', onPress: goTrip }} />
        )
      ) : null}
    </Screen>
  );
}
