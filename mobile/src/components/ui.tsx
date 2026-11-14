// App 本地的小元件，全部用 @domy/design 的代號組起來。
// 規矩：兩款以上的 App 都要用，才搬進 @domy/design。
import type { ReactNode } from 'react';
import { Pressable, View, type StyleProp, type ViewStyle } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { DomyButton, DomyText, T, hitSlopFor, pressFeedback, useDomy } from '@domy/design';

const CHECK = 26;

/** 白底卡片 */
export function Card({ children, tone = 'surface', style }: { children: ReactNode; tone?: 'surface' | 'tint'; style?: StyleProp<ViewStyle> }) {
  const { c } = useDomy();
  return (
    <View
      style={[
        { backgroundColor: tone === 'tint' ? c.tint : c.surface, borderRadius: T.radius.xl, padding: T.space[4], gap: T.space[3] },
        tone === 'tint' ? { borderWidth: T.size.hairline, borderColor: c.soft } : null,
        style,
      ]}
    >
      {children}
    </View>
  );
}

/** 分段切換：同一頁裡換內容用 */
export function Segmented<K extends string>({ value, options, onChange }: { value: K; options: Array<[K, string]>; onChange: (k: K) => void }) {
  const { c } = useDomy();
  return (
    <View accessibilityRole="tablist" style={{ flexDirection: 'row', backgroundColor: c.surfaceMuted, borderRadius: T.radius.md, padding: T.space[1] / 2, gap: T.space[1] / 2 }}>
      {options.map(([k, label]) => {
        const on = k === value;
        return (
          <Pressable
            key={k}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            onPress={() => onChange(k)}
            hitSlop={hitSlopFor(T.size.pickerHeight)}
            style={{ flex: 1, height: T.size.pickerHeight, borderRadius: T.radius.sm, alignItems: 'center', justifyContent: 'center', backgroundColor: on ? c.surface : 'transparent' }}
          >
            <DomyText variant="subheadline" weight="600" tone={on ? 'primary' : 'secondary'} numberOfLines={1}>
              {label}
            </DomyText>
          </Pressable>
        );
      })}
    </View>
  );
}

/** 選項膠囊：選到的用 Soft 底＋Strong 字 */
export function Chip({ label, selected = false, onPress, onSurface = false, disabled = false }: { label: string; selected?: boolean; onPress?: () => void; onSurface?: boolean; disabled?: boolean }) {
  const { c, reduceMotion } = useDomy();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected, disabled }}
      disabled={disabled}
      onPress={onPress}
      hitSlop={hitSlopFor(T.size.buttonCompact)}
      style={({ pressed }) => [
        {
          minHeight: T.size.buttonCompact,
          paddingHorizontal: T.space[4],
          borderRadius: T.radius.pill,
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: selected ? c.soft : onSurface ? c.surfaceMuted : c.surface,
        },
        pressFeedback(pressed, reduceMotion),
      ]}
    >
      <DomyText variant="callout" tone={disabled ? 'disabled' : selected ? 'strong' : 'primary'} numberOfLines={1}>
        {label}
      </DomyText>
    </Pressable>
  );
}

export function ChipRow({ children }: { children: ReactNode }) {
  return <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: T.space[2] }}>{children}</View>;
}

/** 小標籤：只放一眼要看到的狀態 */
export function Tag({ label, tone = 'neutral' }: { label: string; tone?: 'neutral' | 'accent' | 'warn' }) {
  const { c } = useDomy();
  const bg = { neutral: c.surfaceMuted, accent: c.soft, warn: c.destructiveSoft }[tone];
  const textTone = ({ neutral: 'secondary', accent: 'strong', warn: 'destructive' } as const)[tone];
  return (
    <View style={{ backgroundColor: bg, borderRadius: T.radius.pill, paddingHorizontal: T.space[2], paddingVertical: T.space[1] / 2 }}>
      <DomyText variant="caption" tone={textTone}>
        {label}
      </DomyText>
    </View>
  );
}

export function TagRow({ children }: { children: ReactNode }) {
  return <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: T.space[2] }}>{children}</View>;
}

/** 一段要讓人注意的話，可以帶一顆按鈕 */
export function Banner({ text, action }: { text: string; action?: { title: string; onPress: () => void } }) {
  return (
    <Card tone="tint">
      <DomyText variant="subheadline" tone="secondary">
        {text}
      </DomyText>
      {action ? <DomyButton title={action.title} onPress={action.onPress} variant="secondary" size="compact" style={{ alignSelf: 'flex-start' }} /> : null}
    </Card>
  );
}

/** 打勾的列：檢查表、要先訂的 */
export function CheckRow({ checked, title, note, onPress }: { checked: boolean; title: string; note?: string; onPress: () => void }) {
  const { c } = useDomy();
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityState={{ checked }}
      accessibilityLabel={title}
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: T.size.row,
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: T.space[3],
        paddingVertical: T.space[3],
        marginHorizontal: -T.space[4],
        paddingHorizontal: T.space[4],
        backgroundColor: pressed ? c.surfaceMuted : 'transparent',
      })}
    >
      <View
        style={{
          width: CHECK,
          height: CHECK,
          borderRadius: T.radius.pill,
          borderWidth: checked ? 0 : T.size.hairline * 2,
          borderColor: c.fieldBorder,
          backgroundColor: checked ? c.accent : 'transparent',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {checked ? (
          <Svg width={14} height={14} viewBox="0 0 14 14" fill="none">
            <Path d="M2.5 7.5 5.5 10.5 11.5 3.5" stroke={c.onAccent} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
          </Svg>
        ) : null}
      </View>
      <View style={{ flex: 1, gap: T.space[1] }}>
        <DomyText variant="body" tone={checked ? 'secondary' : 'primary'}>
          {title}
        </DomyText>
        {note ? (
          <DomyText variant="footnote" tone="secondary">
            {note}
          </DomyText>
        ) : null}
      </View>
    </Pressable>
  );
}

/** 卡片裡的小標 */
export function Label({ children }: { children: string }) {
  return (
    <DomyText variant="footnote" tone="secondary">
      {children}
    </DomyText>
  );
}

/** 列裡的一段文字（給 DomySection 當一列用） */
export function TextRow({ title, note, right }: { title: string; note?: string; right?: ReactNode }) {
  return (
    <View style={{ minHeight: T.size.row, paddingVertical: T.space[3], flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
      <View style={{ flex: 1, gap: T.space[1] }}>
        <DomyText variant="body">{title}</DomyText>
        {note ? (
          <DomyText variant="footnote" tone="secondary">
            {note}
          </DomyText>
        ) : null}
      </View>
      {right}
    </View>
  );
}
