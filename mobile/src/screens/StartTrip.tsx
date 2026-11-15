// 開一趟：一句一句問，點選項。先問去哪、哪天、幾天、幾點到、幾點走、幾個人、住哪。
// 第一趟多問四題偏好（存進「我」），第二趟起照「平常的你」。
// 每答一題畫面自己往下捲到新的那一題；鍵盤出來時輸入框會被往上推，不會被蓋住。
import { useEffect, useRef, useState, type ComponentRef } from 'react';
import { ScrollView, View } from 'react-native';
import { DomyButton, DomyScreen, DomyText, DomyTextField, T, useDomy, useTabBarClearance } from '@domy/design';
import { Calendar } from '../components/Calendar';
import { Chip, ChipRow } from '../components/ui';
import { CAT, HOTEL, PURPOSE } from '../data/seoul';
import { addDays, fmtDay } from '../domain/dates';
import { PACES, PACE_TEXT } from '../domain/labels';
import { generate, settingsSummary } from '../domain/plan';
import type { BaseKey, Cat, FoodKind, Pace, Part, Purpose, Settings, TripDraft } from '../domain/types';
import { useApp } from '../store';

type Lean = 'street' | 'local' | 'famous' | 'mix';
const LEAN: Record<Lean, { label: string; food: Record<FoodKind, number> }> = {
  street: { label: '市場和路邊小吃為主', food: { street: 3, local: 2, famous: 0, fine: 0 } },
  local: { label: '在地人常去的小館為主', food: { street: 1, local: 3, famous: 1, fine: 0 } },
  famous: { label: '排隊名店也想吃', food: { street: 1, local: 2, famous: 3, fine: 1 } },
  mix: { label: '都來一點', food: { street: 2, local: 2, famous: 2, fine: 1 } },
};
const DAYS = [3, 4, 5, 6, 7, 8, 9, 10, 12, 14];
const ARRIVE: Array<[Part, string]> = [['am', '中午前'], ['pm', '下午'], ['eve', '晚上']];
const LEAVE: Array<[Part, string]> = [['am', '上午'], ['pm', '下午'], ['eve', '晚上']];
const PEOPLE: Array<[number, string]> = [[1, '我一個人'], [2, '兩個人'], [4, '三四個人']];
const BASES = Object.keys(HOTEL) as BaseKey[];

interface Answers extends Partial<TripDraft> {
  /** 住哪一帶答了沒。選「還沒決定」時 base 是空的 */
  baseDone?: boolean;
  /** 住宿名字那題答了沒 */
  stayDone?: boolean;
  purposes?: Purpose[];
  purposesDone?: boolean;
  pace?: Pace;
  lean?: Lean;
  likes?: Cat[];
  likesDone?: boolean;
}

function Bot({ children }: { children: string }) {
  const { c } = useDomy();
  return (
    <View style={{ alignSelf: 'flex-start', maxWidth: '90%', backgroundColor: c.surface, borderRadius: T.radius.xl, paddingVertical: T.space[3], paddingHorizontal: T.space[4] }}>
      <DomyText variant="body">{children}</DomyText>
    </View>
  );
}
function Me({ children }: { children: string }) {
  const { c } = useDomy();
  return (
    <View style={{ alignSelf: 'flex-end', maxWidth: '90%', backgroundColor: c.accent, borderRadius: T.radius.xl, paddingVertical: T.space[3], paddingHorizontal: T.space[4] }}>
      <DomyText variant="headline" tone="onAccent">
        {children}
      </DomyText>
    </View>
  );
}

/** 可以選好幾個的一題：點了會亮，按「選好了」才往下 */
function MultiPick<K extends string>({ options, value, onChange, onDone }: { options: Array<[K, string]>; value: K[]; onChange: (v: K[]) => void; onDone: () => void }) {
  return (
    <View style={{ gap: T.space[3] }}>
      <ChipRow>
        {options.map(([k, label]) => {
          const on = value.includes(k);
          return <Chip key={k} label={label} selected={on} onPress={() => onChange(on ? value.filter((x) => x !== k) : [...value, k])} />;
        })}
      </ChipRow>
      <DomyButton title="選好了" variant="secondary" size="compact" style={{ alignSelf: 'flex-start' }} onPress={onDone} />
    </View>
  );
}

export function StartTrip({ goSettings }: { goSettings: () => void }) {
  const { s, act, today } = useApp();
  const clearance = useTabBarClearance();
  const [a, setA] = useState<Answers>({});
  const [stayText, setStayText] = useState('');
  const scroller = useRef<ComponentRef<typeof ScrollView>>(null);
  const first = !s.settings.tuned;
  const set = (patch: Answers) => setA((p) => ({ ...p, ...patch }));

  const go = () => {
    const { city, start, days, arrive, leave, people, base, stayName } = a;
    if (!city || !start || !days || !arrive || !leave || !people) return;
    act((d) => {
      if (first) {
        const play: Settings['play'] = {};
        (a.likes ?? []).forEach((k) => (play[k] = 1));
        d.settings = { ...d.settings, purposes: a.purposes ?? [], pace: a.pace ?? 'mid', food: LEAN[a.lean ?? 'local'].food, play, tuned: true };
      }
      d.trip = generate({ city, start, days, arrive, leave, people, base, stayName }, d.settings);
      d.chat = [];
      d.checks = Object.fromEntries(Object.entries(d.checks).filter(([k]) => !k.startsWith('b_')));
      d.settingsDirty = false;
      d.debugDay = null;
      return '排好了。每一站下面那行，是為什麼排它。';
    });
  };

  // 一題一題往下長：前一題答了，下一題才出現
  const steps: Array<{ q: string; answered: string | null; options: React.ReactNode }> = [
    {
      q: '這趟要去哪？',
      answered: a.city ? '首爾' : null,
      options: (
        <View style={{ gap: T.space[2] }}>
          <ChipRow>
            <Chip label="首爾" onPress={() => set({ city: 'seoul' })} />
          </ChipRow>
          <DomyText variant="footnote" tone="secondary">
            現在只有首爾，其他城市之後開放。
          </DomyText>
        </View>
      ),
    },
    {
      q: '哪一天出發？',
      answered: a.start ? fmtDay(a.start) : null,
      options: <Calendar min={today} onPick={(iso) => set({ start: iso })} />,
    },
    {
      q: '去幾天？',
      answered: a.days ? `${a.days} 天，${a.start ? fmtDay(addDays(a.start, a.days - 1)) : ''}回來` : null,
      options: (
        <ChipRow>
          {DAYS.map((d) => (
            <Chip key={d} label={`${d} 天`} onPress={() => set({ days: d })} />
          ))}
        </ChipRow>
      ),
    },
    {
      q: '第一天幾點到？',
      answered: a.arrive ? ARRIVE.find((x) => x[0] === a.arrive)![1] : null,
      options: (
        <ChipRow>
          {ARRIVE.map(([k, v]) => (
            <Chip key={k} label={v} onPress={() => set({ arrive: k })} />
          ))}
        </ChipRow>
      ),
    },
    {
      q: '最後一天幾點走？',
      answered: a.leave ? LEAVE.find((x) => x[0] === a.leave)![1] : null,
      options: (
        <ChipRow>
          {LEAVE.map(([k, v]) => (
            <Chip key={k} label={v} onPress={() => set({ leave: k })} />
          ))}
        </ChipRow>
      ),
    },
    {
      q: '幾個人去？',
      answered: a.people ? PEOPLE.find((x) => x[0] === a.people)![1] : null,
      options: (
        <ChipRow>
          {PEOPLE.map(([k, v]) => (
            <Chip key={k} label={v} onPress={() => set({ people: k })} />
          ))}
        </ChipRow>
      ),
    },
    {
      q: '住哪一帶？每天的路線會從住的地方出發、再回來。',
      answered: a.baseDone ? (a.base ? HOTEL[a.base].n : `還沒決定，先當作住${HOTEL[s.settings.base].n}`) : null,
      options: (
        <ChipRow>
          {BASES.map((k) => (
            <Chip key={k} label={HOTEL[k].n} onPress={() => set({ base: k, baseDone: true })} />
          ))}
          <Chip label="還沒決定" onPress={() => set({ base: undefined, baseDone: true, stayDone: true })} />
        </ChipRow>
      ),
    },
    {
      q: '住的地方叫什麼？有訂的話打上來，我記在這趟裡。',
      answered: a.stayDone ? (a.stayName ? a.stayName : '先不填') : null,
      options: (
        <View style={{ gap: T.space[2] }}>
          <DomyTextField
            label="住宿名稱"
            helper="先記著，還不會用它算路線。路線照上一題選的那一帶估。"
            placeholder="例如：明洞某某飯店"
            maxLength={40}
            defaultValue={stayText}
            onChangeText={setStayText}
            returnKeyType="done"
            onSubmitEditing={() => {
              if (stayText.trim()) set({ stayName: stayText.trim(), stayDone: true });
            }}
          />
          <View style={{ flexDirection: 'row', gap: T.space[2] }}>
            <DomyButton title="記下來" variant="secondary" size="compact" disabled={!stayText.trim()} onPress={() => set({ stayName: stayText.trim(), stayDone: true })} />
            <DomyButton title="先不填" variant="plain" size="compact" onPress={() => set({ stayName: undefined, stayDone: true })} />
          </View>
        </View>
      ),
    },
  ];
  if (first) {
    steps.push(
      {
        q: '第一次排，多問四題，之後在「我」都可以改。旅行回來，你希望怎樣？可以選好幾個。',
        answered: a.purposesDone ? (a.purposes?.length ? a.purposes.map((k) => PURPOSE[k]).join('、') : '都可以') : null,
        options: (
          <MultiPick<Purpose>
            options={(Object.keys(PURPOSE) as Purpose[]).map((k) => [k, PURPOSE[k]])}
            value={a.purposes ?? []}
            onChange={(v) => set({ purposes: v })}
            onDone={() => set({ purposesDone: true })}
          />
        ),
      },
      {
        q: '一天想排多滿？',
        answered: a.pace ? `${PACE_TEXT[a.pace].name}：${PACE_TEXT[a.pace].note}` : null,
        options: (
          <View style={{ gap: T.space[2] }}>
            {PACES.map((k) => (
              <View key={k} style={{ gap: T.space[1] }}>
                <Chip label={`${PACE_TEXT[k].name}：${PACE_TEXT[k].note}`} onPress={() => set({ pace: k })} />
                <DomyText variant="footnote" tone="secondary" style={{ paddingHorizontal: T.space[2] }}>
                  例如：{PACE_TEXT[k].example}
                </DomyText>
              </View>
            ))}
          </View>
        ),
      },
      {
        q: '吃的方面，比較偏哪一種？',
        answered: a.lean ? LEAN[a.lean].label : null,
        options: (
          <View style={{ gap: T.space[2] }}>
            {(Object.keys(LEAN) as Lean[]).map((k) => (
              <Chip key={k} label={LEAN[k].label} onPress={() => set({ lean: k })} />
            ))}
          </View>
        ),
      },
      {
        q: '喜歡做什麼？可以選好幾個，沒有特別喜歡的直接按「選好了」。',
        answered: a.likesDone ? (a.likes?.length ? a.likes.map((k) => CAT[k]).join('、') : '都可以') : null,
        options: (
          <MultiPick<Cat>
            options={(Object.keys(CAT) as Cat[]).map((k) => [k, CAT[k]])}
            value={a.likes ?? []}
            onChange={(v) => set({ likes: v })}
            onDone={() => set({ likesDone: true })}
          />
        ),
      },
    );
  }
  const at = steps.findIndex((x) => x.answered == null);
  const shown = at < 0 ? steps : steps.slice(0, at + 1);
  const done = at < 0;

  // 新的一題長出來之後捲到最下面，不然它會躲在分頁列後面
  useEffect(() => {
    const t = setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), T.motion.pressDuration);
    return () => clearTimeout(t);
  }, [shown.length, done]);

  return (
    <DomyScreen title="蘿蔔旅行" scroll={false} bottomInset={0}>
      <ScrollView
        ref={scroller}
        style={{ flex: 1 }}
        automaticallyAdjustKeyboardInsets
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ gap: T.space[3], paddingBottom: clearance }}
      >
        <DomyText variant="subheadline" tone="secondary">
          回答幾題，我把整趟排好。排完想改，用講的就可以。
        </DomyText>
        {shown.map((st, i) => (
          <View key={i} style={{ gap: T.space[3] }}>
            <Bot>{st.q}</Bot>
            {st.answered != null ? <Me>{st.answered}</Me> : st.options}
          </View>
        ))}
        {done ? (
          <View style={{ gap: T.space[3] }}>
            <Bot>
              {first
                ? '好，我照這些排。住宿等級、預算、怎麼移動先用一般的設定，之後在「我」可以改。'
                : `我照平常的你排：${settingsSummary(s.settings)}。`}
            </Bot>
            <DomyButton title="幫我排" fullWidth onPress={go} />
            {!first ? <DomyButton title="我先去改設定" variant="plain" fullWidth onPress={goSettings} /> : null}
          </View>
        ) : null}
        {a.city ? (
          <DomyButton
            title="從頭回答"
            variant="plain"
            size="compact"
            style={{ alignSelf: 'center' }}
            onPress={() => {
              setA({});
              setStayText('');
            }}
          />
        ) : null}
      </ScrollView>
    </DomyScreen>
  );
}
