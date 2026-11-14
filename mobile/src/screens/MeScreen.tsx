// 「我」分頁：平常的我（設一次，每趟照這個排）、備份、測試用的開關。
import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { View } from 'react-native';
import { DomyButton, DomyScreen, DomySection, DomySettingsRow, DomyText, DomyTextField, T, useTabBarClearance } from '@domy/design';
import { Sheet } from '../components/Sheet';
import { Card, Chip, ChipRow, Label, Segmented } from '../components/ui';
import { AVOID, CAT, FLV, FOOD, HOTEL, STAY } from '../data/seoul';
import { foodPct, money } from '../domain/plan';
import type { BaseKey, Cat, FoodKind, Settings } from '../domain/types';
import { blankState, hydrate, useApp } from '../store';

const BUDGETS = [1000, 1500, 2500, 4000];
const MEALS: Array<[number, string]> = [[500, '500'], [1000, '1,000'], [1500, '1,500'], [3000, '3,000'], [0, '不限']];
const PACE_NOTE: Record<Settings['pace'], string> = {
  slow: '一天 1 個大站，下午留白。',
  mid: '一天 2 個大站，每三天一天全輕鬆。',
  fast: '一天 2 個大站，每個時段再加一個小站。',
};

export function MeScreen() {
  const { s, setSettings, act, replaceAll, say } = useApp();
  const clearance = useTabBarClearance();
  const st = s.settings;
  const fp = foodPct(st);
  const [sheet, setSheet] = useState<'import' | 'reset' | null>(null);
  const [backup, setBackup] = useState('');
  const [importErr, setImportErr] = useState<string | undefined>();

  return (
    <DomyScreen title="我" bottomInset={clearance}>
      <DomyText variant="subheadline" tone="secondary" style={{ marginTop: -T.space[4] }}>
        平常的我。設一次，之後每趟都照這個排。{s.trip ? '改了之後，回「這趟」可以照新的重排。' : ''}
      </DomyText>

      <Card>
        <DomyText variant="headline">住</DomyText>
        <Segmented value={st.stay} onChange={(k) => setSettings({ stay: k })} options={(Object.keys(STAY) as Array<Settings['stay']>).map((k) => [k, STAY[k].name])} />
        <DomyText variant="footnote" tone="secondary">
          一晚大約 {money(STAY[st.stay].perNight)}，只拿來估花費。
        </DomyText>
        <Label>通常住哪一帶</Label>
        <Segmented value={st.base} onChange={(k) => setSettings({ base: k })} options={(Object.keys(HOTEL) as BaseKey[]).map((k) => [k, HOTEL[k].n])} />
      </Card>

      <Card>
        <DomyText variant="headline">吃</DomyText>
        <DomyText variant="footnote" tone="secondary">
          四種各自選多常吃，晚餐會照比例分。現在是：
          {(Object.keys(FOOD) as FoodKind[]).filter((k) => fp[k]).map((k) => `${FOOD[k].name} ${fp[k]}%`).join('、')}。
        </DomyText>
        {(Object.keys(FOOD) as FoodKind[]).map((k) => (
          <View key={k} style={{ gap: T.space[2] }}>
            <View>
              <DomyText variant="callout">{FOOD[k].name}</DomyText>
              <DomyText variant="footnote" tone="secondary">
                {FOOD[k].desc}
              </DomyText>
            </View>
            <Segmented value={String(st.food[k])} onChange={(v) => setSettings({ food: { ...st.food, [k]: Number(v) } })} options={FLV.map((l, i) => [String(i), l])} />
          </View>
        ))}
        <Label>一天吃喝預算（每人）</Label>
        <ChipRow>
          {BUDGETS.map((b) => (
            <Chip key={b} onSurface label={money(b)} selected={st.budget === b} onPress={() => setSettings({ budget: b })} />
          ))}
        </ChipRow>
        <Label>一餐最多願意花</Label>
        <ChipRow>
          {MEALS.map(([v, l]) => (
            <Chip key={v} onSurface label={l} selected={st.mealMax === v} onPress={() => setSettings({ mealMax: v })} />
          ))}
        </ChipRow>
        <Label>願意排隊多久</Label>
        <Segmented value={st.queue} onChange={(k) => setSettings({ queue: k })} options={[['no', '不排'], ['some', '半小時內'], ['any', '想吃就排']]} />
        <Label>不吃的</Label>
        <ChipRow>
          {AVOID.map((a) => {
            const on = st.avoid.includes(a);
            return <Chip key={a} onSurface label={a} selected={on} onPress={() => setSettings({ avoid: on ? st.avoid.filter((x) => x !== a) : [...st.avoid, a] })} />;
          })}
        </ChipRow>
        <DomyText variant="footnote" tone="secondary">
          一餐上限、排隊、不吃的，這一版先記著，接上 AI 後才會照這三項挑店。
        </DomyText>
      </Card>

      <Card>
        <DomyText variant="headline">喜歡做什麼</DomyText>
        <DomyText variant="footnote" tone="secondary">
          點一下是喜歡，再點一下是最愛，再點取消。
        </DomyText>
        <ChipRow>
          {(Object.keys(CAT) as Cat[]).map((k) => {
            const v = st.play[k] ?? 0;
            return (
              <Chip
                key={k}
                onSurface
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
      </Card>

      <Card>
        <DomyText variant="headline">節奏</DomyText>
        <Segmented value={st.pace} onChange={(k) => setSettings({ pace: k })} options={[['slow', '慢'], ['mid', '中'], ['fast', '趕']]} />
        <DomyText variant="footnote" tone="secondary">
          {PACE_NOTE[st.pace]}第一天和最後一天都排輕的。
        </DomyText>
        <Label>早上</Label>
        <Segmented value={st.wake} onChange={(k) => setSettings({ wake: k })} options={[['early', '早起'], ['normal', '普通'], ['late', '睡到自然醒']]} />
        <Label>怎麼移動</Label>
        <Segmented value={st.move} onChange={(k) => setSettings({ move: k })} options={[['transit', '地鐵公車'], ['taxi', '多搭計程車'], ['walk', '能走就走']]} />
      </Card>

      <DomySection title="資料" footer="行程、蘿蔔籃、設定都只存在這支手機裡，沒有網路也看得到。換手機前先複製備份。">
        <DomySettingsRow
          label="複製備份"
          onPress={() => {
            Clipboard.setStringAsync(JSON.stringify(s))
              .then(() => say('備份複製好了，貼到備忘錄存起來。'))
              .catch(() => say('複製不了，等一下再試一次。'));
          }}
        />
        <DomySettingsRow label="貼上備份還原" onPress={() => setSheet('import')} />
        <DomySettingsRow label="全部清掉重來" destructive onPress={() => setSheet('reset')} />
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

      <Sheet
        visible={sheet === 'import'}
        title="貼上備份"
        onClose={() => {
          setSheet(null);
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
            setSheet(null);
            say('還原好了。');
          }}
        />
      </Sheet>

      <Sheet visible={sheet === 'reset'} title="全部清掉？" onClose={() => setSheet(null)}>
        <DomyText variant="body">行程、蘿蔔籃、下次再來、設定都會回到一開始的樣子，救不回來。想留著的話，先回上一頁按「複製備份」。</DomyText>
        <DomyButton
          title="清掉"
          variant="destructive"
          fullWidth
          onPress={() => {
            replaceAll(blankState());
            setSheet(null);
            say('全部清掉了。');
          }}
        />
        <DomyButton title="不清了" variant="secondary" fullWidth onPress={() => setSheet(null)} />
      </Sheet>
    </DomyScreen>
  );
}
