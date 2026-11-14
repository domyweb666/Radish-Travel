// 用講的改行程。兩條路：
// 1. 有設定 EXPO_PUBLIC_AI_ENDPOINT → 把提示詞送到自己的後端（後端再轉給 AI），拿回 {reply, ops}
// 2. 沒設定 → 本機只聽得懂幾種固定說法
// 兩條路最後都走 applyOps，所以改動清單和復原是同一套。
import { AREA, CAT, PART, PLACES, PURPOSE } from '../data/seoul';
import {
  allItems,
  areaOf,
  dayStops,
  findItem,
  moveItem,
  newId,
  planText,
  seedOut,
  settingsSummary,
  slotAt,
  swapDays,
  swapParts,
  usedIds,
} from './plan';
import type { AiPlace, Cat, ChatMsg, Op, Part, Seed, Settings, Stop, Trip } from './types';

export interface BrainOut {
  reply: string;
  ops: Op[];
  regen?: boolean;
}

export const LOCAL_HINTS = ['第 2 天上午下午對調', '第 2 天跟第 3 天對調', '第 3 天輕鬆一點', '重排'];
export const AI_HINTS = ['第 2 天上午下午對調', '第 3 天輕鬆一點', '多排一點咖啡廳', '有一天想整天逛街', '雨天備案是什麼'];

const PART_WORD: Record<string, Part> = { 上午: 'am', 下午: 'pm', 晚上: 'eve' };

/** 沒接 AI 時的本機指令。聽不懂就老實說聽不懂 */
export function localBrain(msg: string, t: Trip): BrainOut {
  let m: RegExpMatchArray | null;
  const find = (name: string) => {
    const k = name.trim();
    if (!k) return undefined;
    return allItems(t).find((x) => x.it.n.includes(k) || k.includes(x.it.n.replace(/（.*?）/g, '')));
  };
  if (/重排|重新排/.test(msg)) return { reply: '好，整趟重排一次。', ops: [], regen: true };
  if ((m = msg.match(/第\s*(\d+)\s*天.*第\s*(\d+)\s*天.*(對調|交換|互換)/))) {
    return { reply: `第 ${m[1]} 天和第 ${m[2]} 天整天對調了。`, ops: [{ op: 'swapDays', a: +m[1], b: +m[2] }] };
  }
  if ((m = msg.match(/第\s*(\d+)\s*天.*(對調|交換|互換)/))) {
    return { reply: `第 ${m[1]} 天的上午和下午對調了。`, ops: [{ op: 'swapParts', day: +m[1], a: 'am', b: 'pm' }] };
  }
  if ((m = msg.match(/把?(.+?)(?:移|搬|挪|改|放)到?第\s*(\d+)\s*天\s*(上午|下午|晚上)?/))) {
    const x = find(m[1]);
    if (x) {
      const part = PART_WORD[m[3]] ?? x.s.part;
      return { reply: `「${x.it.n}」移到第 ${m[2]} 天${PART[part]}了。`, ops: [{ op: 'move', id: x.it.id, day: +m[2], part }] };
    }
  }
  if ((m = msg.match(/(?:不要|拿掉|刪掉|移除|不去)(.+)/))) {
    const x = find(m[1].replace(/了|吧|。/g, ''));
    if (x) return { reply: `「${x.it.n}」拿掉了，放進下次再來。`, ops: [{ op: 'remove', id: x.it.id }] };
  }
  if ((m = msg.match(/第\s*(\d+)\s*天.*(輕鬆|少一點|太累|太滿)/))) {
    const stops = dayStops(t, +m[1]);
    const x = stops.find((s) => s.it.s === 'L') ?? stops[0];
    if (x) return { reply: `第 ${m[1]} 天拿掉「${x.it.n}」，鬆一點。`, ops: [{ op: 'remove', id: x.it.id }] };
  }
  return {
    reply: '這一版還沒接上 AI，我只聽得懂幾種說法：「第 3 天上午下午對調」「第 2 天跟第 4 天對調」「把景福宮移到第 4 天上午」「不要樂天世界」「第 3 天輕鬆一點」「重排」。',
    ops: [],
  };
}

function mkPlace(t: Trip, o: string | AiPlace | undefined): Stop | null {
  if (typeof o === 'string') {
    const p = PLACES.find((q) => q.id === o);
    if (!p || usedIds(t).has(p.id)) return null;
    return { ...p, status: 'kept', swaps: 0, why: '跟 AI 討論時加的' };
  }
  if (!o || typeof o !== 'object' || !o.n) return null;
  const lat = Number(o.lat);
  const lng = Number(o.lng);
  const okLL = lat > 33 && lat < 39 && lng > 124 && lng < 131;
  const c = (o.c && o.c in CAT ? o.c : 'sight') as Cat;
  return {
    id: newId('ai'),
    n: String(o.n).slice(0, 40),
    kr: String(o.kr ?? '').slice(0, 60),
    a: '',
    s: o.s === 'L' ? 'L' : 'S',
    c,
    tip: String(o.tip ?? '').slice(0, 80),
    lat: okLL ? lat : null,
    lng: okLL ? lng : null,
    ai: true,
    status: 'kept',
    swaps: 0,
    why: 'AI 提的，還沒核對過',
  };
}

const where = (day: number, part: Part) => `第 ${day} 天${PART[part] ?? ''}`;

/** 把一串動作套到行程上。changes 是給人看的「哪一站從哪到哪」，notes 是沒做成的原因 */
export function applyOps(t: Trip, seeds: Seed[], ops: unknown): { changes: string[]; notes: string[] } {
  const changes: string[] = [];
  const notes: string[] = [];
  if (!Array.isArray(ops)) return { changes, notes };
  (ops as Op[]).slice(0, 20).forEach((o) => {
    try {
      let err: string | null = null;
      if (o.op === 'move') {
        const x = findItem(t, o.id);
        const from = x ? where(x.s.day, x.s.part) : '';
        err = moveItem(t, o.id, +o.day, o.part);
        if (!err && x) changes.push(`「${x.it.n}」${from} → ${where(+o.day, o.part)}`);
      } else if (o.op === 'swapParts') {
        err = swapParts(t, +o.day, o.a, o.b);
        if (!err) changes.push(`第 ${o.day} 天${PART[o.a]}和${PART[o.b]}對調`);
      } else if (o.op === 'swapDays') {
        err = swapDays(t, +o.a, +o.b);
        if (!err) changes.push(`第 ${o.a} 天和第 ${o.b} 天整天對調`);
      } else if (o.op === 'remove') {
        const it = seedOut(t, seeds, o.id, '用講的改行程時拿掉的');
        if (it) changes.push(`「${it.n}」→ 下次再來`);
        else err = '找不到要拿掉的那一站';
      } else if (o.op === 'add') {
        const sl = slotAt(t, +o.day, o.part);
        const p = mkPlace(t, o.id ?? o.place);
        if (!sl) err = `${where(+o.day, o.part)}你在路上`;
        else if (!p) err = '要加的地方不在候選裡';
        else {
          sl.items.push(p);
          if (o.part !== 'eve') sl.rest = false;
          changes.push(`加了「${p.n}」在${where(+o.day, o.part)}`);
        }
      } else if (o.op === 'replace') {
        const x = findItem(t, o.id);
        const p = mkPlace(t, o.with);
        if (!x || !p) err = '換不了，找不到其中一個';
        else {
          x.s.items[x.s.items.indexOf(x.it)] = p;
          changes.push(`「${x.it.n}」換成「${p.n}」`);
        }
      } else if (o.op === 'rest') {
        const sl = slotAt(t, +o.day, o.part);
        if (sl) {
          sl.rest = !!o.on;
          changes.push(`${where(+o.day, o.part)}${o.on ? '改成留白' : '取消留白'}`);
        } else err = '那個時段你在路上';
      }
      if (err) notes.push(err);
    } catch {
      notes.push('有一步沒做成');
    }
  });
  return { changes, notes };
}

/* ---------- 接 AI 的那條路 ---------- */
export const AI_ENDPOINT: string = process.env.EXPO_PUBLIC_AI_ENDPOINT ?? '';
export const aiReady = () => AI_ENDPOINT.length > 0;

export function aiPrompt(msg: string, t: Trip, st: Settings, chat: ChatMsg[]): string {
  const used = usedIds(t);
  const cand = PLACES.filter((p) => !used.has(p.id))
    .map((p) => `[${p.id}] ${p.n}(${p.s === 'L' ? '大' : '小'},${CAT[p.c]},${AREA[p.a]}${p.b ? ',要先訂' : ''})`)
    .join('\n');
  const hist = chat
    .filter((m) => m.r !== 'sys')
    .slice(-8)
    .map((m) => (m.r === 'me' ? '使用者：' : '你：') + m.t)
    .join('\n');
  return `你是旅遊行程 app「蘿蔔旅行」裡的助手，幫一位台灣使用者調整他的首爾行程。用繁體中文、口語、簡短回答（三句內），不要用 markdown、不要用表情符號。

規則：
- 一天最多 2 個大站。使用者堅持要超過時照做，但在 reply 裡提醒會累。
- 第一天和最後一天只排小站。標「在路上」的時段不能排東西。
- 同一個半天的站盡量在同一帶，減少來回跑。
- 你不知道即時資訊。營業時間、票價、是否需要預約都不要講成確定的事，說「去之前查一下」。
- 要加新的地方時，優先從候選清單挑（用它的 id）。清單裡沒有適合的，才自己提一個真實存在的首爾地點，給中文名、韓文名、類別、大小、大概經緯度。
- 使用者只是問問題、沒有要改行程時，ops 給空陣列。

使用者的習慣：${settingsSummary(st)}。這趟的目的：${PURPOSE[t.purpose]}，${t.people || 1} 人，${t.start} 出發。

目前行程（方括號裡是 id）：
${planText(t, true)}
還沒用到的候選：
${cand}

${hist ? '前面的對話：\n' + hist + '\n\n' : ''}使用者現在說：${msg}

只回一個 JSON 物件，不要有其他文字：
{"reply":"給使用者看的話","ops":[...]}
ops 可用的動作：
{"op":"move","id":"p3","day":2,"part":"am"}        把一站移到某天某時段（part: am/pm/eve）
{"op":"swapParts","day":2,"a":"am","b":"pm"}       同一天兩個時段對調
{"op":"swapDays","a":2,"b":4}                      兩天整天對調
{"op":"remove","id":"p3"}                          拿掉（會放進下次再來）
{"op":"add","day":3,"part":"pm","id":"p12"}        從候選加進來
{"op":"add","day":3,"part":"pm","place":{"n":"中文名","kr":"韓文名","c":"eat|shop|fun|sight|art|nature|cafe|night|kpop","s":"L|S","tip":"一句須知","lat":37.5,"lng":127.0}}
{"op":"replace","id":"p3","with":"p12"}            換成候選裡的另一個（with 也可以是上面那種 place 物件）
{"op":"rest","day":3,"part":"pm","on":true}        把某個時段設成留白或取消留白`;
}

/** 送到自己的後端。後端要回 {reply, ops}，或是 {text: "…含 JSON 的文字…"} */
export async function askRemote(prompt: string): Promise<BrainOut> {
  const res = await fetch(AI_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data: unknown = await res.json();
  const obj = data as { reply?: unknown; ops?: unknown; text?: unknown };
  const parsed = typeof obj.text === 'string' ? JSON.parse((obj.text.match(/\{[\s\S]*\}/) ?? ['{}'])[0]) : obj;
  return { reply: String(parsed.reply ?? '好了。').slice(0, 600), ops: Array.isArray(parsed.ops) ? parsed.ops : [] };
}

export const hasAiPlace = (ops: Op[]) => ops.some((o) => (o.op === 'add' && !!o.place) || (o.op === 'replace' && typeof o.with === 'object'));
