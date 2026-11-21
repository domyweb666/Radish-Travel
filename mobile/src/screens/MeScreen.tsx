// 「我」分頁：平常的我（設一次，每趟照這個排）、備份、測試用的開關。
// 主畫面只是一張清單，每列寫著現在的值；點一列才打開那一項來改。
import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { View } from 'react-native';
import { DomyButton, DomyListRow, DomyScreen, DomySection, DomySettingsRow, DomyText, DomyTextField, T, useTabBarClearance } from '@domy/design';
import { AllergyCard } from '../components/AllergyCard';
import { Sheet } from '../components/Sheet';
import { Card, Chip, ChipRow, Label, Segmented, TextRow } from '../components/ui';
import { ALLERGENS, AVOID, CAT, FLV, FOOD, HOTEL, MEH, PURPOSE, STAY } from '../data/seoul';
import { BODIES, BODY_NOTE, BODY_TEXT, INTEREST_TAGS, PACES, PACE_TEXT, WALKS, WALK_TEXT } from '../domain/labels';
import { foodPct, money } from '../domain/plan';
import { learnedText, unlearn } from '../domain/prefs';
import type { BaseKey, Cat, FoodKind, Purpose, Settings } from '../domain/types';
import { blankState, hydrate, useApp } from '../store';

type Opt<V> = { v: V; label: string; note?: string };
const PACE: Array<Opt<Settings['pace']>> = PACES.map((k) => ({ v: k, label: PACE_TEXT[k].name, note: PACE_TEXT[k].note }));
const PACE_EXAMPLES = PACES.map((k) => `${PACE_TEXT[k].name}的一天：${PACE_TEXT[k].example}。`).join('\n');
const WAKE: Array<Opt<Settings['wake']>> = [
  { v: 'early', label: '早起' },
  { v: 'normal', label: '普通' },
  { v: 'late', label: '睡到自然醒', note: '上午不排主要景點' },
];
const MOVE: Array<Opt<Settings['move']>> = [
  { v: 'transit', label: '地鐵公車' },
  { v: 'taxi', label: '多搭計程車' },
  { v: 'walk', label: '能走就走' },
];
const WALK: Array<Opt<Settings['walk']>> = WALKS.map((k) => ({ v: k, label: WALK_TEXT[k].name, note: WALK_TEXT[k].note }));
const BASE: Array<Opt<BaseKey>> = (Object.keys(HOTEL) as BaseKey[]).map((k) => ({ v: k, label: HOTEL[k].n }));
const STAYS: Array<Opt<Settings['stay']>> = (Object.keys(STAY) as Array<Settings['stay']>).map((k) => ({
  v: k,
  label: STAY[k].name,
  note: `一晚大約 ${money(STAY[k].perNight)}，只拿來估花費`,
}));
const BUDGET: Array<Opt<number>> = [1000, 1500, 2500, 4000].map((b) => ({ v: b, label: money(b) }));

const labelOf = <V,>(opts: Array<Opt<V>>, v: V) => opts.find((o) => o.v === v)?.label ?? '';

type Editing = 'purposes' | 'pace' | 'wake' | 'move' | 'base' | 'stay' | 'budget' | 'food' | 'avoid' | 'play' | 'walk' | 'body' | 'learned' | 'import' | 'reset' | null;

/** 單選的一張卡：選了就關 */
function PickSheet<V extends string | number>({ title, options, value, onPick, onClose, footer }: { title: string; options: Array<Opt<V>>; value: V; onPick: (v: V) => void; onClose: () => void; footer?: string }) {
  return (
    <Sheet visible title={title} onClose={onClose}>
      <DomySection footer={footer}>
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
  const likeNames = [...likes.map((k) => CAT[k]), ...st.tags];
  const likesText = likeNames.length ? (likeNames.length > 2 ? `${likeNames[0]}等 ${likeNames.length} 種` : likeNames.join('、')) : '都可以';
  const eatParts = [st.allergy.length ? `過敏 ${st.allergy.length} 樣` : '', st.avoid.length ? `不吃 ${st.avoid.length} 樣` : '', st.meh.length ? `不愛 ${st.meh.length} 樣` : ''].filter(Boolean);
  const purposeText = st.purposes.length ? st.purposes.map((k) => PURPOSE[k]).join('、') : '都可以';

  return (
    <DomyScreen title="我" bottomInset={clearance}>
      <DomySection title="平常的我" footer={`設一次，之後每趟都照這個排。${s.trip ? '改了之後，回「這趟」可以照新的重排。' : ''}`}>
        <DomySettingsRow label="旅行回來想怎樣" value={purposeText} onPress={() => setEditing('purposes')} />
        <DomySettingsRow label="一天排多滿" value={labelOf(PACE, st.pace)} onPress={() => setEditing('pace')} />
        <DomySettingsRow label="吃的偏好" value={`${FOOD[topFood].name}為主`} onPress={() => setEditing('food')} />
        <DomySettingsRow label="過敏和不吃的" value={eatParts.length ? eatParts.join('、') : '沒有'} onPress={() => setEditing('avoid')} />
        <DomySettingsRow label="喜歡做什麼" value={likesText} onPress={() => setEditing('play')} />
        <DomySettingsRow label="早上" value={labelOf(WAKE, st.wake)} onPress={() => setEditing('wake')} />
        <DomySettingsRow label="怎麼移動" value={labelOf(MOVE, st.move)} onPress={() => setEditing('move')} />
        <DomySettingsRow label="一天能走多少" value={labelOf(WALK, st.walk)} onPress={() => setEditing('walk')} />
        <DomySettingsRow label="身體上要避開的" value={st.body.length ? st.body.map((k) => BODY_TEXT[k]).join('、') : '沒有'} onPress={() => setEditing('body')} />
        <DomySettingsRow label="住哪一帶" value={labelOf(BASE, st.base)} onPress={() => setEditing('base')} />
      </DomySection>

      <DomySection footer="你在行程上拿掉一站、選了「以後不排」，會記在這裡。每一條都寫著是哪一次記的。">
        <DomySettingsRow label="從行程學到的" value={st.learned.length ? `${st.learned.length} 條` : '還沒有'} onPress={() => setEditing('learned')} />
      </DomySection>

      <DomySection title="預算" footer="只拿來估這趟大概花多少，不會影響排哪些站。">
        <DomySettingsRow label="住宿" value={labelOf(STAYS, st.stay)} onPress={() => setEditing('stay')} />
        <DomySettingsRow label="一天吃喝" value={money(st.budget)} onPress={() => setEditing('budget')} />
      </DomySection>

      <DomySection title="資料" footer="行程、去過的旅行、照片、設定都只存在這支手機裡，沒有網路也看得到。換手機前先複製備份；備份裡沒有照片，照片要另外留。">
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

      {s.trip && s.guideSeen ? (
        <DomySection>
          <DomySettingsRow
            label="再看一次操作說明"
            onPress={() => {
              act((d) => void (d.guideSeen = false));
              say('回到「這趟」就會再帶一次。');
            }}
          />
        </DomySection>
      ) : null}

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

      {editing === 'pace' ? <PickSheet title="一天排多滿" options={PACE} value={st.pace} onPick={(v) => setSettings({ pace: v })} onClose={close} footer={PACE_EXAMPLES} /> : null}
      {editing === 'wake' ? <PickSheet title="早上" options={WAKE} value={st.wake} onPick={(v) => setSettings({ wake: v })} onClose={close} /> : null}
      {editing === 'walk' ? <PickSheet title="一天能走多少" options={WALK} value={st.walk} onPick={(v) => setSettings({ walk: v })} onClose={close} footer="站和站之間的距離是照直線估的；逛一個景點裡面要走多少，這裡算不到。" /> : null}
      {editing === 'move' ? <PickSheet title="怎麼移動" options={MOVE} value={st.move} onPick={(v) => setSettings({ move: v })} onClose={close} /> : null}
      {editing === 'base' ? <PickSheet title="通常住哪一帶" options={BASE} value={st.base} onPick={(v) => setSettings({ base: v })} onClose={close} /> : null}
      {editing === 'stay' ? <PickSheet title="住宿" options={STAYS} value={st.stay} onPick={(v) => setSettings({ stay: v })} onClose={close} /> : null}
      {editing === 'budget' ? <PickSheet title="一天吃喝（每人）" options={BUDGET} value={st.budget} onPick={(v) => setSettings({ budget: v })} onClose={close} /> : null}

      <Sheet visible={editing === 'purposes'} title="旅行回來想怎樣" onClose={close}>
        <DomyText variant="subheadline" tone="secondary">
          可以選好幾個，選到的那幾類會排得比較多。都不選就是都可以。
        </DomyText>
        <ChipRow>
          {(Object.keys(PURPOSE) as Purpose[]).map((k) => {
            const on = st.purposes.includes(k);
            return <Chip key={k} label={PURPOSE[k]} selected={on} onPress={() => setSettings({ purposes: on ? st.purposes.filter((x) => x !== k) : [...st.purposes, k] })} />;
          })}
        </ChipRow>
        <DomyButton title="好了" fullWidth onPress={close} />
      </Sheet>

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

      <Sheet visible={editing === 'avoid'} title="過敏和不吃的" onClose={close}>
        <DomyText variant="subheadline" tone="secondary">
          分三層，越上面越嚴。這一版吃的站只排到「哪一帶、吃哪一種」，還沒有指定店家，所以我沒辦法照這些幫你挑店。用講的改行程時，AI 會照這三層來。
        </DomyText>
        <View style={{ gap: T.space[2] }}>
          <DomyText variant="headline">過敏，不能出錯</DomyText>
          <DomyText variant="footnote" tone="secondary">
            有選的話，每個吃的站都會提醒你，還會給你一張韓文告知卡，點餐前拿給店員看。
          </DomyText>
          <ChipRow>
            {ALLERGENS.map((a) => {
              const on = st.allergy.includes(a.n);
              return <Chip key={a.n} label={a.n} selected={on} onPress={() => setSettings({ allergy: on ? st.allergy.filter((x) => x !== a.n) : [...st.allergy, a.n] })} />;
            })}
          </ChipRow>
        </View>
        <AllergyCard list={st.allergy} />
        <View style={{ gap: T.space[2] }}>
          <DomyText variant="headline">絕對不吃</DomyText>
          <ChipRow>
            {AVOID.map((a) => {
              const on = st.avoid.includes(a);
              return <Chip key={a} label={a} selected={on} onPress={() => setSettings({ avoid: on ? st.avoid.filter((x) => x !== a) : [...st.avoid, a], meh: st.meh.filter((x) => x !== a) })} />;
            })}
          </ChipRow>
        </View>
        <View style={{ gap: T.space[2] }}>
          <DomyText variant="headline">不愛，但同行的人想吃可以</DomyText>
          <ChipRow>
            {MEH.map((a) => {
              const on = st.meh.includes(a);
              return <Chip key={a} label={a} selected={on} onPress={() => setSettings({ meh: on ? st.meh.filter((x) => x !== a) : [...st.meh, a], avoid: st.avoid.filter((x) => x !== a) })} />;
            })}
          </ChipRow>
        </View>
        <DomyButton title="好了" fullWidth onPress={close} />
      </Sheet>

      <Sheet visible={editing === 'body'} title="身體上要避開的" onClose={close}>
        <DomyText variant="subheadline" tone="secondary">
          可以選好幾個。有選的，排行程時會照下面寫的做。
        </DomyText>
        {BODIES.map((k) => {
          const on = st.body.includes(k);
          return (
            <View key={k} style={{ gap: T.space[1] }}>
              <ChipRow>
                <Chip label={BODY_TEXT[k]} selected={on} onPress={() => setSettings({ body: on ? st.body.filter((x) => x !== k) : [...st.body, k] })} />
              </ChipRow>
              <DomyText variant="footnote" tone="secondary">
                {BODY_NOTE[k]}
              </DomyText>
            </View>
          );
        })}
        <DomyButton title="好了" fullWidth onPress={close} />
      </Sheet>

      <Sheet visible={editing === 'learned'} title="從行程學到的" onClose={close}>
        {st.learned.length ? (
          <DomySection footer="拿掉之後，下一次排行程就會再排到它。拿掉可以復原。">
            {st.learned.map((l) => (
              <TextRow
                key={l.id}
                title={`以後${learnedText(l)}`}
                note={l.source}
                right={<DomyButton title="拿掉" variant="plain" size="compact" accessibilityLabel={`拿掉：以後${learnedText(l)}`} onPress={() => act((d) => (unlearn(d.settings, l.id) ? `拿掉了：以後${learnedText(l)}。` : undefined), { undoable: true })} />}
              />
            ))}
          </DomySection>
        ) : (
          <Card>
            <DomyText variant="body">還沒有。在行程上點一站、按「不想去這一站」、選「以後不排」，這裡就會多一條。</DomyText>
          </Card>
        )}
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
        <Label>更細的</Label>
        <ChipRow>
          {INTEREST_TAGS.map((t) => {
            const on = st.tags.includes(t);
            return <Chip key={t} label={t} selected={on} onPress={() => setSettings({ tags: on ? st.tags.filter((x) => x !== t) : [...st.tags, t] })} />;
          })}
        </ChipRow>
        <DomyTextField
          label="其他想做的"
          helper="上面沒有的，自己寫。例如：想去看棒球、想找二手唱片行。"
          placeholder="想到什麼寫什麼"
          maxLength={80}
          defaultValue={st.wish}
          onEndEditing={(e) => setSettings({ wish: e.nativeEvent.text.trim() })}
        />
        <DomyText variant="footnote" tone="secondary">
          「更細的」和「其他想做的」這一版先記著，還不會照它排。接上 AI 之後，排行程和用講的改都會看這兩項。
        </DomyText>
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
        <DomyText variant="body">所有的旅行、下次再來、設定都會回到一開始的樣子，救不回來。想留著的話，先回上一頁按「複製備份」。</DomyText>
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
