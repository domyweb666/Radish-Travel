// 用講的改行程。每次改完，在對話裡列出哪一站從哪到哪，可以復原上一步。
import { useEffect, useRef, useState, type ComponentRef } from 'react';
import { Pressable, ScrollView, TextInput, View } from 'react-native';
import { DomyButton, DomyText, T, typeStyle, useDomy } from '@domy/design';
import { IconSend } from '../components/icons';
import { Sheet } from '../components/Sheet';
import { Card, Chip } from '../components/ui';
import { AI_HINTS, LOCAL_HINTS, aiPrompt, aiReady, applyOps, askRemote, hasAiPlace, localBrain, type BrainOut } from '../domain/chat';
import { generate, warnings } from '../domain/plan';
import type { ChatMsg } from '../domain/types';
import { useApp } from '../store';

const FIRST = '行程排好了。想怎麼改直接說，例如哪天太滿、哪一站不想去、想多一點什麼。我改完會列出動了哪幾站。';

function Bubble({ m }: { m: ChatMsg }) {
  const { c } = useDomy();
  if (m.r === 'sys') {
    return (
      <DomyText variant="footnote" tone="secondary" style={{ paddingHorizontal: T.space[2] }}>
        {m.t}
      </DomyText>
    );
  }
  const me = m.r === 'me';
  return (
    <View
      style={{
        alignSelf: me ? 'flex-end' : 'flex-start',
        maxWidth: '86%',
        backgroundColor: me ? c.accent : c.surface,
        borderRadius: T.radius.xl,
        paddingVertical: T.space[3],
        paddingHorizontal: T.space[4],
        gap: T.space[2],
      }}
    >
      <DomyText variant="body" tone={me ? 'onAccent' : 'primary'}>
        {m.t}
      </DomyText>
      {m.changes?.length ? (
        <View style={{ gap: T.space[1], borderTopWidth: T.size.hairline, borderTopColor: c.separator, paddingTop: T.space[2] }}>
          <DomyText variant="caption" tone="secondary">
            這次改了
          </DomyText>
          {m.changes.map((ch, i) => (
            <DomyText key={i} variant="subheadline" tone="strong">
              {ch}
            </DomyText>
          ))}
        </View>
      ) : null}
    </View>
  );
}

export function ChatSheet({ onClose }: { onClose: () => void }) {
  const { c } = useDomy();
  const { s, act, undo, canUndo } = useApp();
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const scroller = useRef<ComponentRef<typeof ScrollView>>(null);
  const remote = aiReady();
  const needConsent = remote && !s.aiConsent;

  useEffect(() => {
    const t = setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), T.motion.pressDuration);
    return () => clearTimeout(t);
  }, [s.chat.length, busy]);

  if (!s.trip) return null;

  const send = async (raw: string) => {
    const msg = raw.trim();
    if (!msg || busy || !s.trip) return;
    setBusy(true);
    setText('');
    act((d) => {
      d.chat.push({ r: 'me', t: msg });
    });
    let out: BrainOut;
    let failed = false;
    if (remote) {
      try {
        out = await askRemote(aiPrompt(msg, s.trip, s.settings, s.chat));
      } catch {
        failed = true;
        out = localBrain(msg, s.trip);
      }
    } else {
      out = localBrain(msg, s.trip);
    }
    const willChange = !!out.regen || out.ops.length > 0;
    act(
      (d) => {
        if (!d.trip) return;
        if (failed) d.chat.push({ r: 'sys', t: 'AI 這次沒回好，先用內建的簡單指令。' });
        const changes: string[] = [];
        if (out.regen) {
          const { purpose, start, days, arrive, leave, people, flight } = d.trip;
          d.trip = { ...generate({ purpose, start, days, arrive, leave, people }, d.settings, true), flight };
          d.settingsDirty = false;
          changes.push('整趟照現在的設定重排了');
        }
        const r = applyOps(d.trip, d.seeds, out.ops);
        changes.push(...r.changes);
        d.chat.push({ r: 'ai', t: out.reply, changes });
        [...r.notes, ...warnings(d.trip)].forEach((n) => d.chat.push({ r: 'sys', t: n }));
        if (hasAiPlace(out.ops)) d.chat.push({ r: 'sys', t: 'AI 自己加的地點還沒核對過，去之前查一下。' });
        d.chat = d.chat.slice(-40);
      },
      { undoable: willChange },
    );
    setBusy(false);
  };

  const hints = remote ? AI_HINTS : LOCAL_HINTS;

  return (
    <Sheet visible title="用講的改行程" onClose={onClose} scroll={false}>
      {needConsent ? (
        <Card>
          <DomyText variant="headline">第一次用之前，先講清楚</DomyText>
          <DomyText variant="body">
            用講的改行程時，這三樣會送到蘿蔔旅行的伺服器，再轉給 AI 服務（Anthropic 的 Claude）：你打的那句話、這趟的行程、「我」分頁裡平常的習慣。
          </DomyText>
          <DomyText variant="body">不會送你的位置、名字、聯絡方式。</DomyText>
          <DomyButton title="知道了，開始用" fullWidth onPress={() => act((d) => void (d.aiConsent = true))} />
        </Card>
      ) : (
        <>
          <ScrollView ref={scroller} style={{ flex: 1 }} contentContainerStyle={{ gap: T.space[2], paddingVertical: T.space[2] }} keyboardShouldPersistTaps="handled">
            <Bubble m={{ r: 'ai', t: FIRST }} />
            {s.chat.map((m, i) => (
              <Bubble key={i} m={m} />
            ))}
            {busy ? <Bubble m={{ r: 'ai', t: '想一下…' }} /> : null}
          </ScrollView>
          <View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} keyboardShouldPersistTaps="handled" contentContainerStyle={{ gap: T.space[2] }}>
              {canUndo ? (
                <Chip
                  label="復原上一步"
                  selected
                  onPress={() => {
                    undo();
                    act((d) => {
                      d.chat.push({ r: 'sys', t: '復原了上一步。' });
                    });
                  }}
                />
              ) : null}
              {hints.map((h) => (
                <Chip key={h} label={h} disabled={busy} onPress={() => send(h)} />
              ))}
            </ScrollView>
          </View>
          <View style={{ flexDirection: 'row', gap: T.space[2], alignItems: 'center' }}>
            <TextInput
              accessibilityLabel="跟我說要怎麼改"
              value={text}
              onChangeText={setText}
              placeholder="跟我說要怎麼改"
              placeholderTextColor={c.textSecondary}
              selectionColor={c.accent}
              maxLength={200}
              returnKeyType="send"
              onSubmitEditing={() => send(text)}
              style={[
                typeStyle('body'),
                {
                  flex: 1,
                  minHeight: T.size.field,
                  borderRadius: T.radius.pill,
                  backgroundColor: c.surface,
                  borderWidth: T.size.hairline,
                  borderColor: c.fieldBorder,
                  color: c.textPrimary,
                  paddingHorizontal: T.space[4],
                },
              ]}
            />
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="送出"
              accessibilityState={{ disabled: busy || !text.trim() }}
              disabled={busy || !text.trim()}
              onPress={() => send(text)}
              style={{
                width: T.size.field,
                height: T.size.field,
                borderRadius: T.radius.pill,
                backgroundColor: text.trim() && !busy ? c.accent : c.surfaceMuted,
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <IconSend color={text.trim() && !busy ? c.onAccent : c.textDisabled} />
            </Pressable>
          </View>
          <DomyText variant="footnote" tone="secondary">
            {remote ? '已接上 AI。它不知道即時的營業時間和票價，去之前查一下。' : '這一版還沒接上 AI，只聽得懂上面那幾種說法。'}
          </DomyText>
        </>
      )}
    </Sheet>
  );
}
