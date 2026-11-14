// 一天的地圖：住的地方＋這天每一站，下面是站與站之間怎麼去。
import { DomySection, DomyText } from '@domy/design';
import { Sheet } from '../components/Sheet';
import { TextRow } from '../components/ui';
import { addDays, fmtDay } from '../domain/dates';
import { dayLegs, dayStops, hotelPt, legText } from '../domain/plan';
import { useApp } from '../store';
import { DayMap, type MapPoint } from './DayMap';

export function MapSheet({ day, onClose }: { day: number; onClose: () => void }) {
  const { s } = useApp();
  if (!s.trip) return null;
  const h = hotelPt(s.settings);
  const stops = dayStops(s.trip, day).map((x) => x.it);
  const legs = dayLegs(s.trip, s.settings, day);
  const points: MapPoint[] = [
    { key: 'home', title: `住的地方（${h.n}）`, subtitle: h.kr, lat: h.lat, lng: h.lng, home: true },
    ...stops.flatMap((it) => (it.lat != null && it.lng != null ? [{ key: it.id, title: it.n, subtitle: it.kr, lat: it.lat, lng: it.lng }] : [])),
  ];
  return (
    <Sheet visible title={`第 ${day} 天 ${fmtDay(addDays(s.trip.start, day - 1))}`} onClose={onClose}>
      {stops.length ? <DayMap points={points} /> : null}
      {stops.length ? (
        <DomySection footer="點的位置是大概的，距離是直線加三成、時間是估的。真的要走的時候，從每一站的卡跳去 Naver 地圖。">
          {stops.map((it, i) => (
            <TextRow key={it.id} title={`${i + 1}. ${it.n}`} note={`${i === 0 ? '從住的地方出發・' : ''}${legText(legs[i])}`} />
          ))}
          <TextRow title={`回住的地方（${h.n}）`} note={legText(legs[legs.length - 1])} />
        </DomySection>
      ) : (
        <DomyText variant="body" tone="secondary">
          這天沒有排站。
        </DomyText>
      )}
    </Sheet>
  );
}
