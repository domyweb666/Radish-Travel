// 「我」分頁：平常的我（設一次，每趟照這個排）、備份、測試用的開關。
// 主畫面只是一張清單，每列寫著現在的值；點一列才打開那一項來改。
import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { View } from 'react-native';
import { DomyButton, DomyListRow, DomyScreen, DomySection, DomySettingsRow, DomyText, DomyTextField, T, useTabBarClearance } from '@domy/design';
import { Sheet } from '../components/Sheet';
import { Chip, ChipRow, Segmented } from '../components/ui';
import { AVOID, CAT, FLV, FOOD, HOTEL, STAY } from '../data/seoul';
import { foodPct, money } from '../domain/plan';
import type { BaseKey, Cat, FoodKind, Settings } from '../domain/types';
import { blankState, hydrate, useApp } from '../store';

type Opt<V> = { v: V; label: string; note?: string };
const PACE: Array<Opt<Settings['pace']>> = [
  { v: 'slow', label: '慢', note: '一天 1 個大站，下午留白' },
  { v: 'mid', label: '中', note: '一天 2 個大站，每三天一天全輕鬆' },
  { v: 'fast', label: '趕', note: '一天 2 個大站，每個時段再加一個小站' },
];
const WAKE: Array<Opt<Settings['wake']>> = [
  { v: 'early', label: '早起' },
  { v: 'normal', label: '普通' },
  { v: 'late', label: '睡到自然醒', note: '上午不排大站' },
];
const MOVE: Array<Opt<Settings['move']>> = [
  { v: 'transit', label: '地鐵公車' },
  { v: 'taxi', label: '多搭計程車' },
  { v: 'walk', label: '能走就走' },
];
const BASE: Array<Opt<BaseKey>> = (Object.keys(HOTEL) as BaseKey[]).map((k) => ({ v: k, label: HOTEL[k].n }));
const STAYS: Array<Opt<Settings['stay']>> = (Object.keys(STAY) as Array<Settings['stay']>).map((k) => ({
  v: k,
  label: STAY[k].name,
  note: `一晚大約 ${money(STAY[k].perNight)}，只拿來估花費`,
}));
const BUDGET: Array<Opt<number>> = [1000, 1500, 2500, 4000].map((b) => ({ v: b, label: money(b) }));

const labelOf = <V,>(opts: Array<Opt<V>>, v: V) => opts.find((o) => o.v === v)?.label ?? '';

type Editing = 'pace' | 'wake' | 'move' | 'base' | 'stay' | 'budget' | 'food' | 'avoid' | 'play' | 'import' | 'reset' | null;

/** 單選的一張卡：選了就關 */
function PickSheet<V extends string | number>({ title, options, value, onPick, onClose }: { title: string; options: Array<Opt<V>>; value: V; onPick: (v: V) => void; onClose: () => void }) {
  return (
    <Sheet visible title={title} onClose={onClose}>
      <DomySection>
        {options.map((o) => (
          <DomyListRow
            key={String(o.v)}
            meta={o.note}
            title={o.label}
            selected={o.v === value}
            onPress={() => {
              onPick(o.v);
              onClose();
            }}
          />
        ))}
      </DomySection>
    </Sheet>
  );
}

export function MeScreen() {
  const { s, setSettings, act, replaceAll, say } = useApp();
  const clearance = useTabBarClearance();
  const st = s.settings;
  const fp = foodPct(st);
  const [editing, setEditing] = useState<Editing>(null);
  const [backup, setBackup] = useState('');
  const [importErr, setImportErr] = useState<string | undefined>();
  const close = () => setEditing(null);

  const kinds = Object.keys(FOOD) as FoodKind[];
  const topFood = [...kinds].sort((a, b) => fp[b] - fp[a])[0];
  const likes = (Object.keys(CAT) as Cat[]).filter((k) => st.play[k]);
  const likesText = likes.length ? (likes.length > 2 ? `${CAT[likes[0]]}等 ${likes.length} 種` : likes.map((k) => CAT[k]).join('、')) : '都可以';

  return (
    <DomyScreen title="我" bottomInset={clearance}>
      <DomySection title="平常的我" footer={`設一次，之後每趟都照這個排。${s.trip ? '改了之後，回「這趟」可以照新的重排。' : ''}`}>
        <DomySettingsRow label="節奏" value={labelOf(PACE, st.pace)} onPress={() => setEditing('pace')} />
        <DomySettingsRow label="吃的偏好" value={`${FOOD[topFood].name}為主`} onPress={() => setEditing('food')} />
        <DomySettingsRow label="不吃的" value={st.avoid.length ? st.avoid.join('、') : '沒有'} onPress={() => setEditing('avoid')} />
        <DomySettingsRow label="喜歡做什麼" value={likesText} onPress={() => setEditing('play')} />
        <DomySettingsRow label="早上" value={labelOf(WAKE, st.wake)} onPress={() => setEditing('wake')} />
        <DomySettingsRow label="怎麼移動" value={labelOf(MOVE, st.move)} onPress={() => setEditing('move')} />
        <DomySettingsRow label="住哪一帶" value={labelOf(BASE, st.base)} onPress={() => setEditing('base')} />
      </DomySection>

      <DomySection title="預算" footer="只拿來估這趟大概花多少，不會影響排哪些站。">
        <DomySettingsRow label="住宿" value={labelOf(STAYS, st.stay)} onPress={() => setEditing('stay')} />
        <DomySettingsRow label="一天吃喝" value={money(st.budget)} onPress={() => setEditing('budget')} />
      </DomySection>

      <DomySection title="資料" footer="行程、蘿蔔籃、設定都只存在這支手機裡，沒有網路也看得到。換手機前先複製備份。">
        <DomySettingsRow
          label="複製備份"
          onPress={() => {
            Clipboard.setStringAsync(JSON.stringify(s))
              .then(() => say('備份複製好了，貼到備忘錄存起來。'))
              .catch(() => say('複製不了，等一下再試一次。'));
          }}
        />
        <DomySettingsRow label="貼上備份還原" onPress={() => setEditing('import')} />
        <DomySettingsRow label="全部清掉重來" destructive onPress={() => setEditing('reset')} />
      </DomySection>

      {s.trip ? (
        <DomySection title="測試用" footer="正式版會照日期自動進入旅途中。這裡讓你出發前先看旅途中的樣子。">
          <DomySettingsRow
            label="假裝現在是"
            picker={{
              value: s.debugDay == null ? '照日期' : s.debugDay > s.trip.days ? '已經回來' : `第 ${s.debugDay} 天`,
              onPress: () =>
                act((d) => {
                  if (!d.trip) return;
                  d.debugDay = d.debugDay == null ? 1 : d.debugDay > d.trip.days ? null : d.debugDay + 1;
                }),
            }}
          />
        </DomySection>
      ) : null}

      {editing === 'pace' ? <PickSheet title="節奏" options={PACE} value={st.pace} onPick={(v) => setSettings({ pace: v })} onClose={close} /> : null}
      {editing === 'wake' ? <PickSheet title="早上" options={WAKE} value={st.wake} onPick={(v) => setSettings({ wake: v })} onClose={close} /> : null}
      {editing === 'move' ? <PickSheet title="怎麼移動" options={MOVE} value={st.move} onPick={(v) => setSettings({ move: v })} onClose={close} /> : null}
      {editing === 'base' ? <PickSheet title="通常住哪一帶" options={BASE} value={st.base} onPick={(v) => setSettings({ base: v })} onClose={close} /> : null}
      {editing === 'stay' ? <PickSheet title="住宿" options={STAYS} value={st.stay} onPick={(v) => setSettings({ stay: v })} onClose={close} /> : null}
      {editing === 'budget' ? <PickSheet title="一天吃喝（每人）" options={BUDGET} value={st.budget} onPick={(v) => setSettings({ budget: v })} onClose={close} /> : null}

      <Sheet visible={editing === 'food'} title="吃的偏好" onClose={close}>
        <DomyText variant="subheadline" tone="secondary">
          四種各自選多常吃，晚餐會照比例分。現在是：
          {kinds.filter((k) => fp[k]).map((k) => `${FOOD[k].name} ${fp[k]}%`).join('、')}。
        </DomyText>
        {kinds.map((k) => (
          <View key={k} style={{ gap: T.space[2] }}>
            <View>
              <DomyText variant="headline">{FOOD[k].name}</DomyText>
              <DomyText variant="footnote" tone="secondary">
                {FOOD[k].desc}
              </DomyText>
            </View>
            <Segmented value={String(st.food[k])} onChange={(v) => setSettings({ food: { ...st.food, [k]: Number(v) } })} options={FLV.map((l, i) => [String(i), l])} />
          </View>
        ))}
        <DomyButton title="好了" fullWidth onPress={close} />
      </Sheet>

      <Sheet visible={editing === 'avoid'} title="不吃的" onClose={close}>
        <DomyText variant="subheadline" tone="secondary">
          可以選好幾個。這一版先記著，還不會照這個挑店；接上 AI 之後，排餐廳和用講的改行程都會避開。
        </DomyText>
        <ChipRow>
          {AVOID.map((a) => {
            const on = st.avoid.includes(a);
            return <Chip key={a} label={a} selected={on} onPress={() => setSettings({ avoid: on ? st.avoid.filter((x) => x !== a) : [...st.avoid, a] })} />;
          })}
        </ChipRow>
        <DomyButton title="好了" fullWidth onPress={close} />
      </Sheet>

      <Sheet visible={editing === 'play'} title="喜歡做什麼" onClose={close}>
        <DomyText variant="subheadline" tone="secondary">
          點一下是喜歡，再點一下是最愛，再點取消。都不選就是都可以。
        </DomyText>
        <ChipRow>
          {(Object.keys(CAT) as Cat[]).map((k) => {
            const v = st.play[k] ?? 0;
            return (
              <Chip
                key={k}
                label={v === 2 ? `${CAT[k]}・最愛` : CAT[k]}
                selected={v > 0}
                onPress={() => {
                  const play = { ...st.play };
                  if (v === 0) play[k] = 1;
                  else if (v === 1) play[k] = 2;
                  else delete play[k];
                  setSettings({ play });
                }}
              />
            );
          })}
        </ChipRow>
        <DomyButton title="好了" fullWidth onPress={close} />
      </Sheet>

      <Sheet
        visible={editing === 'import'}
        title="貼上備份"
        onClose={() => {
          close();
          setImportErr(undefined);
        }}
      >
        <DomyTextField
          label="備份內容"
          helper="把之前複製的備份整段貼進來。現在手機裡的資料會被換掉。"
          error={importErr}
          multiline
          value={backup}
          onChangeText={(v) => {
            setBackup(v);
            setImportErr(undefined);
          }}
          style={{ minHeight: T.size.heroButton }}
        />
        <DomyButton
          title="還原"
          fullWidth
          onPress={() => {
            let ok = false;
            try {
              ok = !!(JSON.parse(backup) as { settings?: unknown }).settings;
            } catch {
              ok = false;
            }
            if (!ok) {
              setImportErr('這段不是蘿蔔旅行的備份。請回備忘錄把整段重新複製一次。');
              return;
            }
            replaceAll(hydrate(backup));
            setBackup('');
            close();
            say('還原好了。');
          }}
        />
      </Sheet>

      <Sheet visible={editing === 'reset'} title="全部清掉？" onClose={close}>
        <DomyText variant="body">行程、蘿蔔籃、下次再來、設定都會回到一開始的樣子，救不回來。想留著的話，先回上一頁按「複製備份」。</DomyText>
        <DomyButton
          title="清掉"
          variant="destructive"
          fullWidth
          onPress={() => {
            replaceAll(blankState());
            close();
            say('全部清掉了。');
          }}
        />
        <DomyButton title="不清了" variant="secondary" fullWidth onPress={close} />
      </Sheet>
    </DomyScreen>
  );
}
