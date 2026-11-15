// 行程設定：排好之後回來改這趟的基本資料。
// 只改名稱、封面、出發日、人數、住宿名稱，行程原樣留著。
// 改天數、到離時間、住哪一帶要整趟重排；已經有去過的站時不讓重排，免得去過的紀錄被排掉。
import { useState } from 'react';
import { DomyButton, DomyText } from '@domy/design';
import { Sheet } from '../components/Sheet';
import { TripForm, formOf, missingOf, type TripFormValue } from '../components/TripForm';
import { Banner } from '../components/ui';
import { allItems, draftOf, generate } from '../domain/plan';
import { useApp } from '../store';

export function TripSettingsSheet({ onClose }: { onClose: () => void }) {
  const { s, act, today } = useApp();
  const trip = s.trip;
  const [form, setForm] = useState<TripFormValue | null>(() => (trip ? formOf(trip) : null));
  if (!trip || !form) return null;

  const missing = missingOf(form);
  const regen = form.days !== trip.days || form.arrive !== trip.arrive || form.leave !== trip.leave || form.base !== trip.base;
  const visited = allItems(trip).some((x) => x.it.status === 'pulled');
  const blocked = regen && visited;

  const save = () => {
    const { start, days, arrive, leave, people } = form;
    if (!start || !days || !arrive || !leave || !people) return;
    act(
      (d) => {
        if (!d.trip) return;
        const patch = { start, days, arrive, leave, people, base: form.base, stayName: form.stayName.trim() || undefined, name: form.name.trim() || undefined, cover: form.cover };
        if (regen) {
          d.trip = { ...generate({ ...draftOf(d.trip), ...patch }, d.settings), flight: d.trip.flight };
          d.settingsDirty = false;
          return '行程設定改了，整趟重排了。手動改過的地方也一起重排了。';
        }
        Object.assign(d.trip, patch);
        return '行程設定改好了。';
      },
      { undoable: true },
    );
    onClose();
  };

  return (
    <Sheet visible title="行程設定" onClose={onClose}>
      <TripForm value={form} onChange={setForm} minStart={trip.start < today ? trip.start : today} fallbackBase={s.settings.base} />
      {blocked ? (
        <Banner text="這趟已經有去過的站。天數、到離時間、住哪一帶現在不能改，改了會整趟重排，去過的紀錄會不見。其他欄位可以改。" />
      ) : regen ? (
        <Banner text="你改了天數、到離時間或住哪一帶。存了會整趟重排，手動改過的地方也會重排。存完可以復原。" />
      ) : null}
      {missing.length ? (
        <DomyText variant="footnote" tone="secondary">
          還沒填：{missing.join('、')}
        </DomyText>
      ) : null}
      <DomyButton title={regen && !blocked ? '存起來，整趟重排' : '存起來'} fullWidth disabled={missing.length > 0 || blocked} onPress={save} />
    </Sheet>
  );
}
