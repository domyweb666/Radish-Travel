// 開一趟：基本資料一頁填完（TripForm），按「幫我排」。
// 第一趟在表單下面多問四題偏好（存進「我」），第二趟起照「平常的你」。
// 鍵盤出來時輸入框會被往上推，不會被蓋住。
import { useState } from 'react';
import { ScrollView, View } from 'react-native';
import { DomyButton, DomyScreen, DomyText, T, useTabBarClearance } from '@domy/design';
import { TripForm, blankForm, missingOf, type TripFormValue } from '../components/TripForm';
import { Card, Chip, ChipRow, Label } from '../components/ui';
import { CAT, PURPOSE } from '../data/seoul';
import { fmtDay } from '../domain/dates';
import { PACES, PACE_TEXT } from '../domain/labels';
import { generate, settingsSummary } from '../domain/plan';
import { openShelved, tripTitle } from '../domain/tripActions';
import type { Cat, FoodKind, Pace, Purpose, Settings } from '../domain/types';
import { useApp } from '../store';

type Lean = 'street' | 'local' | 'famous' | 'mix';
const LEAN: Record<Lean, { label: string; food: Record<FoodKind, number> }> = {
  street: { label: '市場和路邊小吃為主', food: { street: 3, local: 2, famous: 0, fine: 0 } },
  local: { label: '在地人常去的小館為主', food: { street: 1, local: 3, famous: 1, fine: 0 } },
  famous: { label: '排隊名店也想吃', food: { street: 1, local: 2, famous: 3, fine: 1 } },
  mix: { label: '都來一點', food: { street: 2, local: 2, famous: 2, fine: 1 } },
};

interface Prefs {
  purposes: Purpose[];
  pace: Pace;
  lean: Lean;
  likes: Cat[];
}

/** 可以選好幾個：點了會亮，再點一次取消 */
function Multi<K extends string>({ options, value, onChange }: { options: Array<[K, string]>; value: K[]; onChange: (v: K[]) => void }) {
  return (
    <ChipRow>
      {options.map(([k, label]) => {
        const on = value.includes(k);
        return <Chip key={k} label={label} selected={on} onPress={() => onChange(on ? value.filter((x) => x !== k) : [...value, k])} />;
      })}
    </ChipRow>
  );
}

function Group({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={{ gap: T.space[2] }}>
      <Label>{label}</Label>
      {children}
    </View>
  );
}

export function StartTrip({ goSettings }: { goSettings: () => void }) {
  const { s, act, today } = useApp();
  const clearance = useTabBarClearance();
  const [form, setForm] = useState<TripFormValue>(blankForm);
  const [prefs, setPrefs] = useState<Prefs>({ purposes: [], pace: 'mid', lean: 'local', likes: [] });
  const first = !s.settings.tuned;
  const missing = missingOf(form);
  // 從「旅行」按開新的一趟進來的：原本那趟在「其他排好的」最上面，可以直接回去
  const back = s.shelf[0];

  const go = () => {
    const { start, days, arrive, leave, people } = form;
    if (!start || !days || !arrive || !leave || !people) return;
    act((d) => {
      if (first) {
        const play: Settings['play'] = {};
        prefs.likes.forEach((k) => (play[k] = 1));
        d.settings = { ...d.settings, purposes: prefs.purposes, pace: prefs.pace, food: LEAN[prefs.lean].food, play, tuned: true };
      }
      d.trip = generate({ city: 'seoul', start, days, arrive, leave, people, base: form.base, stayName: form.stayName.trim() || undefined, name: form.name.trim() || undefined, cover: form.cover }, d.settings);
      d.chat = [];
      d.checks = Object.fromEntries(Object.entries(d.checks).filter(([k]) => !k.startsWith('b_')));
      d.settingsDirty = false;
      d.debugDay = null;
      return '排好了。每一站下面那行，是為什麼排它。';
    });
  };

  return (
    <DomyScreen title="開一趟" scroll={false} bottomInset={0}>
      <ScrollView
        style={{ flex: 1 }}
        automaticallyAdjustKeyboardInsets
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ gap: T.space[5], paddingBottom: clearance }}
      >
        <DomyText variant="subheadline" tone="secondary">
          填好這一頁，我把整趟排好。排完想改，用講的就可以；這一頁之後也能回來改。
        </DomyText>

        <TripForm value={form} onChange={setForm} minStart={today} fallbackBase={s.settings.base} />

        {first ? (
          <Card>
            <DomyText variant="headline">第一次排，多問四題</DomyText>
            <DomyText variant="subheadline" tone="secondary">
              不選也可以，我先用一般的排法。之後在「我」都能改。
            </DomyText>
            <Group label="旅行回來，你希望怎樣？可以選好幾個">
              <Multi<Purpose> options={(Object.keys(PURPOSE) as Purpose[]).map((k) => [k, PURPOSE[k]])} value={prefs.purposes} onChange={(v) => setPrefs({ ...prefs, purposes: v })} />
            </Group>
            <Group label="一天想排多滿">
              <View style={{ gap: T.space[2] }}>
                {PACES.map((k) => (
                  <View key={k} style={{ gap: T.space[1] }}>
                    <Chip label={`${PACE_TEXT[k].name}：${PACE_TEXT[k].note}`} selected={prefs.pace === k} onSurface onPress={() => setPrefs({ ...prefs, pace: k })} />
                    <DomyText variant="footnote" tone="secondary" style={{ paddingHorizontal: T.space[2] }}>
                      例如：{PACE_TEXT[k].example}
                    </DomyText>
                  </View>
                ))}
              </View>
            </Group>
            <Group label="吃的方面，比較偏哪一種">
              <View style={{ gap: T.space[2] }}>
                {(Object.keys(LEAN) as Lean[]).map((k) => (
                  <Chip key={k} label={LEAN[k].label} selected={prefs.lean === k} onSurface onPress={() => setPrefs({ ...prefs, lean: k })} />
                ))}
              </View>
            </Group>
            <Group label="喜歡做什麼？可以選好幾個">
              <Multi<Cat> options={(Object.keys(CAT) as Cat[]).map((k) => [k, CAT[k]])} value={prefs.likes} onChange={(v) => setPrefs({ ...prefs, likes: v })} />
            </Group>
          </Card>
        ) : (
          <DomyText variant="subheadline" tone="secondary">
            我照平常的你排：{settingsSummary(s.settings)}。
          </DomyText>
        )}

        <View style={{ gap: T.space[2] }}>
          {missing.length ? (
            <DomyText variant="footnote" tone="secondary" style={{ textAlign: 'center' }}>
              還沒填：{missing.join('、')}
            </DomyText>
          ) : null}
          <DomyButton title="幫我排" fullWidth disabled={missing.length > 0} onPress={go} />
          {!first ? <DomyButton title="我先去改平常的習慣" variant="plain" fullWidth onPress={goSettings} /> : null}
          {back ? (
            <DomyButton
              title={`不排了，回「${tripTitle(back.trip)}・${fmtDay(back.trip.start)}出發」`}
              variant="plain"
              fullWidth
              onPress={() => act((d) => openShelved(d, back.id))}
            />
          ) : null}
        </View>
      </ScrollView>
    </DomyScreen>
  );
}
