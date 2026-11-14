// 網頁預覽沒有 Apple 地圖元件，這裡只說明，站的順序在下面的清單。
import { DomyText } from '@domy/design';
import { Card } from '../components/ui';
import type { MapPoint } from './DayMap';

export type { MapPoint };

export function DayMap({ points }: { points: MapPoint[] }) {
  return (
    <Card>
      <DomyText variant="subheadline" tone="secondary">
        網頁預覽畫不出地圖。在 iPhone 上這裡是 Apple 地圖，會標出住的地方和這天的 {Math.max(points.length - 1, 0)} 站，可以按「我在哪」。
      </DomyText>
    </Card>
  );
}
