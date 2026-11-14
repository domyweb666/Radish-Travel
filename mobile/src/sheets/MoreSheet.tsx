// 「更多」：不常用的動作收在這裡，主畫面只留看行程和用講的改。
import { Share } from 'react-native';
import { DomySection, DomySettingsRow } from '@domy/design';
import { Sheet } from '../components/Sheet';
import { TextRow } from '../components/ui';
import { dayStops, seedOut, slotAt, swapParts } from '../domain/plan';
import { archiveTrip, shareText } from '../domain/tripActions';
import { useApp } from '../store';

export function MoreSheet({ day, onClose, onAdd }: { day: number; onClose: () => void; onAdd: () => void }) {
  const { s, act, phase } = useApp();
  const trip = s.trip;
  if (!trip) return null;
  const canSwap = !!slotAt(trip, day, 'am') && !!slotAt(trip, day, 'pm');
  const big = phase?.kind === 'trip' ? dayStops(trip, phase.day).find((x) => x.it.status === 'kept' && x.it.s === 'L') : undefined;
  return (
    <Sheet visible title="更多" onClose={onClose}>
      <DomySection title={`第 ${day} 天`}>
        {canSwap ? (
          <DomySettingsRow
            label="上午和下午對調"
            onPress={() => {
              act((d) => (d.trip ? (swapParts(d.trip, day, 'am', 'pm') ?? `第 ${day} 天上午和下午對調了。`) : undefined), { undoable: true });
              onClose();
            }}
          />
        ) : null}
        {big ? (
          <DomySettingsRow
            label="今天排輕一點"
            value={`先不去${big.it.n}`}
            onPress={() => {
              act(
                (d) => {
                  if (!d.trip) return;
                  seedOut(d.trip, d.seeds, big.it.id, '那天想排輕一點');
                  return `今天的大站「${big.it.n}」先放到下次再來。`;
                },
                { undoable: true },
              );
              onClose();
            }}
          />
        ) : null}
        <DomySettingsRow label="自己加一站" onPress={onAdd} />
      </DomySection>
      <DomySection title="這趟">
        <DomySettingsRow label="傳給旅伴看" onPress={() => void Share.share({ message: shareText(trip) }).catch(() => {})} />
        <DomySettingsRow
          label="這趟不排了，收起來"
          onPress={() => {
            act((d) => archiveTrip(d), { undoable: true });
            onClose();
          }}
        />
      </DomySection>
      {s.pool.length ? (
        <DomySection title="你加的、順路有空再去">
          {s.pool.map((n, i) => (
            <TextRow key={i} title={n} />
          ))}
        </DomySection>
      ) : null}
    </Sheet>
  );
}
