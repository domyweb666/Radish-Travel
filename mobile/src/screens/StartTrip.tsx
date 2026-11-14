// 開一趟：一句一句問，點選項。第一趟多問三題偏好，第二趟起照「平常的你」。
import { useState } from 'react';
import { View } from 'react-native';
import { DomyButton, DomyScreen, DomyText, T, useDomy, useTabBarClearance } from '@domy/design';
import { BUDDY_SIZE, RadishBuddy } from '../components/buddy/RadishBuddy';
import { Calendar } from '../components/Calendar';
import { Chip, ChipRow } from '../components/ui';
import { CAT, PURPOSE } from '../data/seoul';
import { addDays, fmtDay } from '../domain/dates';
import { generate, settingsSummary } from '../domain/plan';
import type { Cat, FoodKind, Pace, Part, Purpose, Settings, TripDraft } from '../domain/types';
import { useApp } from '../store';

type Lean = 'street' | 'local' | 'famous' | 'mix';
const LEAN: Record<Lean, { label: string; food: Record<FoodKind, number> }> = {
  street: { label: '市場和路邊小吃為主', food: { street: 3, local: 2, famous: 0, fine: 0 } },
  local: { label: '在地人常去的小館為主', food: { street: 1, local: 3, famous: 1, fine: 0 } },
  famous: { label: '排隊名店也想吃', food: { street: 1, local: 2, famous: 3, fine: 1 } },
  mix: { label: '都來一點', food: { street: 2, local: 2, famous: 2, fine: 1 } },
};
const PACE: Record<Pace, string> = { slow: '慢慢來，一天一個重點', mid: '中等，一天兩個重點', fast: '趕一點，能排就排' };
const DAYS = [3, 4, 5, 6, 7, 8, 9, 10, 12, 14];
const ARRIVE: Array<[Part, string]> = [['am', '中午前'], ['pm', '下午'], ['eve', '晚上']];
const LEAVE: Array<[Part, string]> = [['am', '上午'], ['pm', '下午'], ['eve', '晚上']];
const PEOPLE: Array<[number, string]> = [[1, '我一個人'], [2, '兩個人'], [4, '三四個人']];

interface Answers extends Partial<TripDraft> {
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

export function StartTrip({ goSettings }: { goSettings: () => void }) {
  const { s, act, today } = useApp();
  const clearance = useTabBarClearance();
  const [a, setA] = useState<Answers>({});
  const first = !s.settings.tuned;
  const set = (patch: Answers) => setA((p) => ({ ...p, ...patch }));

  const go = () => {
    const { purpose, start, days, arrive, leave, people } = a;
    if (!purpose || !start || !days || !arrive || !leave || !people) return;
    act((d) => {
      if (first) {
        const play: Settings['play'] = {};
        (a.likes ?? []).forEach((k) => (play[k] = 1));
        d.settings = { ...d.settings, pace: a.pace ?? 'mid', food: LEAN[a.lean ?? 'local'].food, play, tuned: true };
      }
      d.trip = generate({ purpose, start, days, arrive, leave, people }, d.settings);
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
      q: '要去首爾對吧。這趟回來，你希望怎樣？',
      answered: a.purpose ? PURPOSE[a.purpose] : null,
      options: (
        <ChipRow>
          {(Object.keys(PURPOSE) as Purpose[]).map((k) => (
            <Chip key={k} label={PURPOSE[k]} onPress={() => set({ purpose: k })} />
          ))}
        </ChipRow>
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
  ];
  if (first) {
    steps.push(
      {
        q: '第一次排，多問三題。你旅行的節奏？',
        answered: a.pace ? PACE[a.pace] : null,
        options: (
          <View style={{ gap: T.space[2] }}>
            {(Object.keys(PACE) as Pace[]).map((k) => (
              <Chip key={k} label={PACE[k]} onPress={() => set({ pace: k })} />
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
          <View style={{ gap: T.space[3] }}>
            <ChipRow>
              {(Object.keys(CAT) as Cat[]).map((k) => {
                const on = !!a.likes?.includes(k);
                return <Chip key={k} label={CAT[k]} selected={on} onPress={() => set({ likes: on ? a.likes!.filter((x) => x !== k) : [...(a.likes ?? []), k] })} />;
              })}
            </ChipRow>
            <DomyButton title="選好了" variant="secondary" size="compact" style={{ alignSelf: 'flex-start' }} onPress={() => set({ likesDone: true })} />
          </View>
        ),
      },
    );
  }
  const at = steps.findIndex((x) => x.answered == null);
  const shown = at < 0 ? steps : steps.slice(0, at + 1);
  const done = at < 0;

  return (
    <DomyScreen title="蘿蔔旅行" bottomInset={clearance}>
      <View style={{ gap: T.space[3] }}>
        {/* 還沒答第一題時揮手打招呼，開始答了就安靜站著 */}
        <View style={{ alignItems: 'center' }}>
          <RadishBuddy action={a.purpose ? 'idle' : 'wave'} size={BUDDY_SIZE.hero} />
        </View>
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
        {a.purpose ? <DomyButton title="從頭回答" variant="plain" size="compact" style={{ alignSelf: 'center' }} onPress={() => setA({})} /> : null}
      </View>
    </DomyScreen>
  );
}
