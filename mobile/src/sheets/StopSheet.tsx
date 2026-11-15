// 一站的卡：為什麼排它、須知、當地文字、找路，還有移走、換一個、這次不去。
import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { View } from 'react-native';
import { DomyButton, DomyListRow, DomySection, DomySettingsRow, DomyText, T } from '@domy/design';
import { CatIcon, kindName } from '../components/icons';
import { Sheet } from '../components/Sheet';
import { Card, Chip, ChipRow, Label, Tag, TagRow } from '../components/ui';
import { VisitNote } from '../components/VisitNote';
import { AREA, PART } from '../data/seoul';
import { fmtDay, addDays } from '../domain/dates';
import { PARTS, alternatives, areaOf, bigCount, dayStops, findItem, money, moveItem, replaceWith, seedOut, slotAt, warnings } from '../domain/plan';
import type { Part } from '../domain/types';
import { useApp } from '../store';
import { openApple, openGoogle, openNaver } from './links';

type Mode = 'main' | 'move' | 'swap' | 'show';

export function StopSheet({ id, onClose }: { id: string; onClose: () => void }) {
  const { s, act, phase } = useApp();
  const [mode, setMode] = useState<Mode>('main');
  // 出發之後每一站都可以標成去過：不照順序走、忘記按、回來才補，都從這裡
  const started = phase?.kind === 'trip' || phase?.kind === 'done';
  const setStatus = (status: 'kept' | 'pulled', msg: string) =>
    act(
      (d) => {
        const x = d.trip ? findItem(d.trip, id) : undefined;
        if (!x) return;
        x.it.status = status;
        return msg;
      },
      { undoable: true },
    );
  const [copied, setCopied] = useState(false);
  const trip = s.trip;
  const found = trip ? findItem(trip, id) : undefined;
  const [to, setTo] = useState<{ day: number; part: Part }>(() => ({ day: found?.s.day ?? 1, part: found?.s.part ?? 'am' }));
  if (!trip || !found) return null;
  const { it, s: slot } = found;

  if (mode === 'show') {
    return (
      <Sheet visible title="給司機看" onClose={() => setMode('main')}>
        <Card style={{ alignItems: 'center', paddingVertical: T.space[12] }}>
          <DomyText variant="largeTitle" style={{ textAlign: 'center' }}>
            {it.kr}
          </DomyText>
          <DomyText variant="subheadline" tone="secondary" style={{ textAlign: 'center' }}>
            여기로 가 주세요（請到這裡）
          </DomyText>
        </Card>
      </Sheet>
    );
  }

  if (mode === 'move') {
    const ok = !!slotAt(trip, to.day, to.part);
    return (
      <Sheet visible title={`把「${it.n}」移到`} onClose={() => setMode('main')}>
        <Label>哪一天</Label>
        <ChipRow>
          {Array.from({ length: trip.days }, (_, i) => i + 1).map((d) => (
            <Chip
              key={d}
              label={`第 ${d} 天 ${fmtDay(addDays(trip.start, d - 1))}`}
              selected={to.day === d}
              onPress={() => setTo({ day: d, part: slotAt(trip, d, to.part) ? to.part : (PARTS.find((p) => slotAt(trip, d, p)) ?? to.part) })}
            />
          ))}
        </ChipRow>
        <Label>哪個時段</Label>
        <ChipRow>
          {PARTS.map((p) => {
            const free = !!slotAt(trip, to.day, p);
            return <Chip key={p} label={free ? PART[p] : `${PART[p]}（在路上）`} selected={to.part === p && free} disabled={!free} onPress={() => setTo({ day: to.day, part: p })} />;
          })}
        </ChipRow>
        <DomyText variant="footnote" tone="secondary">
          第 {to.day} 天現在有 {bigCount(trip, to.day)} 個主要景點、共 {dayStops(trip, to.day).length} 站。
        </DomyText>
        <DomyButton
          title="移過去"
          fullWidth
          disabled={!ok}
          onPress={() => {
            act(
              (d) => {
                if (!d.trip) return;
                const err = moveItem(d.trip, id, to.day, to.part);
                return err ?? warnings(d.trip)[0] ?? `「${it.n}」移到第 ${to.day} 天${PART[to.part]}了。`;
              },
              { undoable: true },
            );
            onClose();
          }}
        />
      </Sheet>
    );
  }

  if (mode === 'swap') {
    const alts = alternatives(trip, s.settings, it);
    return (
      <Sheet visible title={`把「${it.n}」換成`} onClose={() => setMode('main')}>
        {it.swaps >= 3 ? (
          <Card>
            <DomyText variant="body">這一站已經換過三輪了。前面那幾個都合你的條件，挑一個就好。想要完全不同的，用講的跟我說。</DomyText>
          </Card>
        ) : alts.length ? (
          <DomySection footer="同一帶、差不多大小的三個。一站最多換三輪。">
            {alts.map((p) => (
              <DomyListRow
                key={p.id}
                meta={`${kindName(p)}・${AREA[p.a]}${p.b ? '・要先訂' : ''}${p.fee ? '・約 ' + money(p.fee) : ''}`}
                title={p.n}
                onPress={() => {
                  act(
                    (d) => {
                      if (!d.trip) return;
                      return replaceWith(d.trip, id, p) ?? `「${it.n}」換成「${p.n}」了。`;
                    },
                    { undoable: true },
                  );
                  onClose();
                }}
              />
            ))}
          </DomySection>
        ) : (
          <Card>
            <DomyText variant="body">這一帶沒有別的候選了。</DomyText>
          </Card>
        )}
      </Sheet>
    );
  }

  return (
    <Sheet visible title={it.n} onClose={onClose}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
        <CatIcon it={it} />
        <View style={{ flex: 1, gap: T.space[1] }}>
          <DomyText variant="subheadline" tone="secondary">
            第 {slot.day} 天{PART[slot.part]}・{areaOf(it)}・{kindName(it)}
          </DomyText>
          <TagRow>
            <Tag label={it.s === 'L' ? '主要景點' : '順路小地方'} />
            {it.b ? <Tag label="要先訂" tone="accent" /> : null}
            {it.ai ? <Tag label="AI 加的・未核對" tone="warn" /> : null}
            {it.mine ? <Tag label="自己加的" /> : null}
            {it.status === 'pulled' ? <Tag label="去過了" tone="accent" /> : null}
          </TagRow>
        </View>
      </View>

      <Card tone="tint">
        <Label>為什麼排這一站</Label>
        <DomyText variant="body">{it.why}</DomyText>
      </Card>

      <Card>
        <Label>每人大概花多少</Label>
        <DomyText variant="body">{it.fee ? `約 ${money(it.fee)}（粗估，沒核對過）` : '這一站還沒有花費資料。'}</DomyText>
        <Label>須知</Label>
        <DomyText variant="body">{it.tip ? `${it.tip}。` : '這一站還沒有須知。'}</DomyText>
        <DomyText variant="footnote" tone="secondary">
          照片、招牌菜、平均消費、營業時間，要等接上地點查證才有。現在去之前請自己查一下。
        </DomyText>
      </Card>

      {it.status === 'pulled' ? (
        <VisitNote
          say={it.say}
          photos={it.photos ?? []}
          onSay={(say) =>
            act((d) => {
              const x = d.trip ? findItem(d.trip, id) : undefined;
              if (x) x.it.say = say;
            })
          }
          onPhotos={(next) =>
            act((d) => {
              const x = d.trip ? findItem(d.trip, id) : undefined;
              if (x) x.it.photos = next;
            })
          }
        />
      ) : null}

      {it.kr ? (
        <>
          <Card>
            <Label>韓文名稱（給司機或路人看）</Label>
            <DomyText variant="title1">{it.kr}</DomyText>
            <View style={{ flexDirection: 'row', gap: T.space[2] }}>
              <DomyButton
                title={copied ? '複製了' : '複製韓文'}
                variant="secondary"
                size="compact"
                onPress={() => {
                  Clipboard.setStringAsync(it.kr).then(() => setCopied(true)).catch(() => {});
                }}
              />
              <DomyButton title="放大給司機看" variant="secondary" size="compact" onPress={() => setMode('show')} />
            </View>
          </Card>
          <DomySection title="找路" footer="這一版只有韓文名稱，沒有門牌地址。接上地點查證後會帶出完整韓文地址。">
            <DomySettingsRow label="用 Naver 地圖找路" value="當地最常用" onPress={() => openNaver(it.kr)} />
            <DomySettingsRow label="用 Google 地圖開" onPress={() => openGoogle(it.kr)} />
            <DomySettingsRow label="用 Apple 地圖開" onPress={() => openApple(it.kr)} />
          </DomySection>
        </>
      ) : (
        <Card>
          <DomyText variant="subheadline" tone="secondary">
            {it.mine ? '這是你自己加的，這一版還不知道它在哪。' : '這一站目前只排到「哪一帶、吃哪一種」，還沒有指定店家。'}
            接上地點查證後，會給店名、韓文地址和地圖連結。
          </DomyText>
        </Card>
      )}

      {it.status === 'kept' ? (
        <View style={{ gap: T.space[2] }}>
          {started ? <DomyButton title="去過了，拔起來" fullWidth onPress={() => setStatus('pulled', `「${it.n}」拔起來了。往下可以寫一句、加照片。`)} /> : null}
          <DomyButton title="移到別的時段" variant="secondary" fullWidth onPress={() => setMode('move')} />
          <DomyButton title="換一個" variant="secondary" fullWidth onPress={() => setMode('swap')} />
          <DomyButton
            title="這次不去，放到下次再來"
            variant="plain"
            fullWidth
            onPress={() => {
              act(
                (d) => {
                  if (!d.trip) return;
                  seedOut(d.trip, d.seeds, id, '你說這次不去');
                  return `「${it.n}」放到下次再來了。`;
                },
                { undoable: true },
              );
              onClose();
            }}
          />
        </View>
      ) : (
        <DomyButton title="按錯了，這站還沒去" variant="plain" fullWidth onPress={() => setStatus('kept', `「${it.n}」改回還沒去。寫的那一句和照片都還在。`)} />
      )}
    </Sheet>
  );
}
