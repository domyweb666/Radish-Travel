// 選出發日的月曆。今天以前的日子不能選。
import { useState } from 'react';
import { Pressable, View } from 'react-native';
import { DomyText, T, useDomy } from '@domy/design';
import { monthGrid } from '../domain/dates';

const WEEK = ['日', '一', '二', '三', '四', '五', '六'];

export function Calendar({ min, value, onPick }: { min: string; value?: string; onPick: (iso: string) => void }) {
  const { c } = useDomy();
  const [y0, m0] = (value ?? min).split('-').map(Number);
  const [ym, setYm] = useState({ y: y0, m: m0 });
  const cells = monthGrid(ym.y, ym.m);
  const [minY, minM] = min.split('-').map(Number);
  const canPrev = ym.y > minY || (ym.y === minY && ym.m > minM);
  const step = (n: number) => {
    const d = new Date(Date.UTC(ym.y, ym.m - 1 + n, 1));
    setYm({ y: d.getUTCFullYear(), m: d.getUTCMonth() + 1 });
  };
  const arrow = (label: string, text: string, onPress: () => void, enabled: boolean) => (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: !enabled }}
      disabled={!enabled}
      onPress={onPress}
      style={{ width: T.size.touch, height: T.size.touch, alignItems: 'center', justifyContent: 'center' }}
    >
      <DomyText variant="title3" tone={enabled ? 'strong' : 'disabled'}>
        {text}
      </DomyText>
    </Pressable>
  );
  return (
    <View style={{ backgroundColor: c.surface, borderRadius: T.radius.xl, padding: T.space[3], gap: T.space[1] }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
        {arrow('上個月', '‹', () => step(-1), canPrev)}
        <DomyText variant="headline">
          {ym.y} 年 {ym.m} 月
        </DomyText>
        {arrow('下個月', '›', () => step(1), true)}
      </View>
      <View style={{ flexDirection: 'row' }}>
        {WEEK.map((w) => (
          <DomyText key={w} variant="caption" tone="secondary" style={{ flex: 1, textAlign: 'center' }}>
            {w}
          </DomyText>
        ))}
      </View>
      {Array.from({ length: cells.length / 7 }, (_, r) => (
        <View key={r} style={{ flexDirection: 'row' }}>
          {cells.slice(r * 7, r * 7 + 7).map((iso, i) => {
            if (!iso) return <View key={i} style={{ flex: 1, height: T.size.touch }} />;
            const off = iso < min;
            const on = iso === value;
            return (
              <Pressable
                key={iso}
                accessibilityRole="button"
                accessibilityLabel={`${ym.m} 月 ${Number(iso.slice(8))} 日，星期${WEEK[i]}`}
                accessibilityState={{ disabled: off, selected: on }}
                disabled={off}
                onPress={() => onPick(iso)}
                style={{ flex: 1, height: T.size.touch, alignItems: 'center', justifyContent: 'center' }}
              >
                <View
                  style={{
                    width: T.size.buttonCompact,
                    height: T.size.buttonCompact,
                    borderRadius: T.radius.pill,
                    alignItems: 'center',
                    justifyContent: 'center',
                    backgroundColor: on ? c.accent : 'transparent',
                  }}
                >
                  <DomyText variant="body" tone={off ? 'disabled' : on ? 'onAccent' : 'primary'}>
                    {Number(iso.slice(8))}
                  </DomyText>
                </View>
              </Pressable>
            );
          })}
        </View>
      ))}
    </View>
  );
}
