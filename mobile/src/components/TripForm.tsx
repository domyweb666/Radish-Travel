// 一趟的基本資料，一頁填完：去哪、哪天、幾天、幾點到幾點走、幾個人、住哪、名稱、封面。
// 開一趟時填一次，排好之後在「行程設定」可以回來改。用講的改行程時 AI 也看得到這些。
import { useState } from 'react';
import { Image, View } from 'react-native';
import { DomyButton, DomyText, DomyTextField, T } from '@domy/design';
import { HOTEL } from '../data/seoul';
import { addDays, fmtDay } from '../domain/dates';
import type { BaseKey, Part, Trip } from '../domain/types';
import { pickPhoto, photoUri } from '../io/photos';
import { useApp } from '../store';
import { Calendar } from './Calendar';
import { Chip, ChipRow, Label } from './ui';

const DAYS = [3, 4, 5, 6, 7, 8, 9, 10, 12, 14];
const ARRIVE: Array<[Part, string]> = [['am', '中午前'], ['pm', '下午'], ['eve', '晚上']];
const LEAVE: Array<[Part, string]> = [['am', '上午'], ['pm', '下午'], ['eve', '晚上']];
const PEOPLE: Array<[number, string]> = [[1, '我一個人'], [2, '兩個人'], [4, '三四個人']];
const BASES = Object.keys(HOTEL) as BaseKey[];
const COVER_H = T.size.heroButton * 2; // domy-ignore: 封面照的高度，只有這裡用

export interface TripFormValue {
  name: string;
  cover?: string;
  start?: string;
  days?: number;
  arrive?: Part;
  leave?: Part;
  people?: number;
  /** 住哪一帶。baseDone 為 true 而 base 是空的，代表「還沒決定」 */
  base?: BaseKey;
  baseDone: boolean;
  stayName: string;
}

export const blankForm = (): TripFormValue => ({ name: '', baseDone: false, stayName: '' });
export const formOf = (t: Trip): TripFormValue => ({
  name: t.name ?? '',
  cover: t.cover,
  start: t.start,
  days: t.days,
  arrive: t.arrive,
  leave: t.leave,
  people: t.people,
  base: t.base,
  baseDone: true,
  stayName: t.stayName ?? '',
});

/** 還沒填的必填欄位，用來告訴使用者為什麼還不能按 */
export function missingOf(v: TripFormValue): string[] {
  const out: string[] = [];
  if (!v.start) out.push('出發日');
  if (!v.days) out.push('去幾天');
  if (!v.arrive) out.push('第一天幾點到');
  if (!v.leave) out.push('最後一天幾點走');
  if (!v.people) out.push('幾個人');
  if (!v.baseDone) out.push('住哪一帶');
  return out;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={{ gap: T.space[2] }}>
      <Label>{label}</Label>
      {children}
    </View>
  );
}

export function TripForm({ value, onChange, minStart, fallbackBase }: { value: TripFormValue; onChange: (v: TripFormValue) => void; minStart: string; fallbackBase: BaseKey }) {
  const { say } = useApp();
  const [picking, setPicking] = useState(false);
  const set = (patch: Partial<TripFormValue>) => onChange({ ...value, ...patch });
  const end = value.start && value.days ? fmtDay(addDays(value.start, value.days - 1)) : null;

  return (
    <View style={{ gap: T.space[5] }}>
      <Field label="去哪">
        <ChipRow>
          <Chip label="首爾" selected />
        </ChipRow>
        <DomyText variant="footnote" tone="secondary">
          現在只有首爾，其他城市之後開放。
        </DomyText>
      </Field>

      <Field label={value.start ? `出發日：${fmtDay(value.start)}` : '出發日'}>
        <Calendar min={minStart} value={value.start} onPick={(iso) => set({ start: iso })} />
      </Field>

      <Field label={end ? `去幾天：${end}回來` : '去幾天'}>
        <ChipRow>
          {DAYS.map((d) => (
            <Chip key={d} label={`${d} 天`} selected={value.days === d} onPress={() => set({ days: d })} />
          ))}
        </ChipRow>
      </Field>

      <Field label="第一天幾點到">
        <ChipRow>
          {ARRIVE.map(([k, label]) => (
            <Chip key={k} label={label} selected={value.arrive === k} onPress={() => set({ arrive: k })} />
          ))}
        </ChipRow>
      </Field>

      <Field label="最後一天幾點走">
        <ChipRow>
          {LEAVE.map(([k, label]) => (
            <Chip key={k} label={label} selected={value.leave === k} onPress={() => set({ leave: k })} />
          ))}
        </ChipRow>
      </Field>

      <Field label="幾個人去">
        <ChipRow>
          {PEOPLE.map(([k, label]) => (
            <Chip key={k} label={label} selected={value.people === k} onPress={() => set({ people: k })} />
          ))}
        </ChipRow>
      </Field>

      <Field label="住哪一帶">
        <ChipRow>
          {BASES.map((k) => (
            <Chip key={k} label={HOTEL[k].n} selected={value.baseDone && value.base === k} onPress={() => set({ base: k, baseDone: true })} />
          ))}
          <Chip label="還沒決定" selected={value.baseDone && !value.base} onPress={() => set({ base: undefined, baseDone: true })} />
        </ChipRow>
        <DomyText variant="footnote" tone="secondary">
          每天的路線會從住的地方出發、再回來。{value.baseDone && !value.base ? `還沒決定的話，先當作住${HOTEL[fallbackBase].n}。` : ''}
        </DomyText>
      </Field>

      <DomyTextField
        label="住宿名稱（可以不填）"
        helper="先記著，還不會用它算路線。路線照上面選的那一帶估。"
        placeholder="例如：明洞某某飯店"
        maxLength={40}
        defaultValue={value.stayName}
        onChangeText={(t) => set({ stayName: t })}
      />

      <DomyTextField
        label="幫這趟取個名字（可以不填）"
        helper="不填的話就叫「首爾幾天」。"
        placeholder="例如：跟媽媽的首爾"
        maxLength={20}
        defaultValue={value.name}
        onChangeText={(t) => set({ name: t })}
      />

      <Field label="封面照片（可以不放）">
        {value.cover ? <Image source={{ uri: photoUri(value.cover) }} accessibilityLabel="這趟的封面照片" style={{ width: '100%', height: COVER_H, borderRadius: T.radius.lg }} /> : null}
        <View style={{ flexDirection: 'row', gap: T.space[2] }}>
          <DomyButton
            title={picking ? '處理中…' : value.cover ? '換一張' : '從相簿挑一張'}
            variant="secondary"
            size="compact"
            disabled={picking}
            onPress={() => {
              setPicking(true);
              pickPhoto()
                .then((ref) => {
                  if (ref) set({ cover: ref });
                })
                .catch(() => say('這張照片放不進來，換一張試試。'))
                .finally(() => setPicking(false));
            }}
          />
          {value.cover ? <DomyButton title="不放了" variant="plain" size="compact" onPress={() => set({ cover: undefined })} /> : null}
        </View>
        <DomyText variant="footnote" tone="secondary">
          會顯示在「旅行」分頁這一趟的旁邊。照片存在這支手機裡，不會上傳。
        </DomyText>
      </Field>
    </View>
  );
}
