import assert from 'node:assert/strict';
import { test } from 'node:test';
import { aiPrompt } from '../src/domain/chat';
import { allItems, alternatives, cost, dayLegs, defaultSettings, draftOf, generate, settingsSummary } from '../src/domain/plan';
import { allergyCard, banned, learn, learnChoices, tripSettings, unlearn } from '../src/domain/prefs';
import type { Settings, Stop, TripDraft } from '../src/domain/types';

const draft = (over: Partial<TripDraft> = {}): TripDraft => ({ start: '2026-12-04', days: 6, arrive: 'am', leave: 'eve', people: 2, ...over });
const stops = (d: TripDraft, st: Settings) => allItems(generate(d, st)).map((x) => x.it);

test('這趟臨時調整：只改這一趟，存好的偏好原樣', () => {
  const st: Settings = { ...defaultSettings(), pace: 'fast', food: { street: 1, local: 2, famous: 3, fine: 2 }, stay: 'nice', budget: 2500 };
  const before = JSON.stringify(st);
  const eff = tripSettings(st, ['elder', 'save']);
  assert.equal(eff.walk, 'less');
  assert.ok(eff.body.includes('stairs'));
  assert.equal(eff.pace, 'mid');
  assert.equal(eff.food.fine, 0);
  assert.equal(eff.stay, 'cheap');
  generate(draft({ tweaks: ['elder', 'save'] }), st);
  assert.equal(JSON.stringify(st), before, '平常的偏好沒被動到');
  assert.equal(tripSettings(st, undefined), st);
});

test('帶長輩：不排坡多階梯多的站，站和站之間超過 500 公尺不用走的', () => {
  const st = defaultSettings();
  assert.ok(stops(draft({ days: 10 }), { ...st, pace: 'fast' }).some((x) => x.up), '平常會排到有坡的站');
  const t = generate(draft({ days: 10, tweaks: ['elder'] }), { ...st, pace: 'fast' });
  assert.ok(allItems(t).every((x) => !x.it.up));
  for (let d = 1; d <= t.days; d++) for (const l of dayLegs(t, st, d)) if (l?.mode === '走路') assert.ok(l.km <= 0.5);
  assert.deepEqual(draftOf(t).tweaks, ['elder'], '重排時這趟的調整還在');
});

test('想省一點、有要慶祝的事：晚餐和花費跟著變', () => {
  const st: Settings = { ...defaultSettings(), food: { street: 1, local: 1, famous: 1, fine: 3 }, stay: 'nice', budget: 4000 };
  const plain = generate(draft(), st);
  const saved = generate(draft({ tweaks: ['save'] }), st);
  assert.ok(allItems(plain).some((x) => x.it.f === 'fine'));
  assert.ok(allItems(saved).every((x) => x.it.f !== 'fine'), '省的那趟不排精緻餐廳');
  assert.ok(cost(saved, st).total < cost(plain, st).total);
  const treat = generate(draft({ tweaks: ['treat'] }), defaultSettings());
  const fine = allItems(treat).filter((x) => x.it.f === 'fine');
  assert.equal(fine.length, 1, '平常不吃精緻餐廳的人，這趟剛好排一餐');
  assert.equal(fine[0].s.day, 3);
  assert.match(fine[0].it.why, /慶祝/);
});

test('以後都不排：某一類、某一站、某一種吃的，排行程和換一個都跳過', () => {
  const st: Settings = { ...defaultSettings(), play: { art: 2 }, food: { street: 2, local: 2, famous: 2, fine: 0 } };
  const t = generate(draft({ days: 8 }), st);
  const art = allItems(t).find((x) => x.it.c === 'art')?.it as Stop;
  assert.ok(art, '最愛博物館的人會排到博物館');
  const choices = learnChoices(art, st);
  assert.deepEqual(choices.map((c) => c.kind), ['place', 'cat']);
  const x = learn(st, choices[1], '測試：你拿掉了' + art.n);
  assert.ok(stops(draft({ days: 8 }), st).every((i) => i.c !== 'art'));
  assert.ok(alternatives(generate(draft(), st), st, { ...art, c: 'sight' }).every((p) => p.c !== 'art'));
  assert.match(settingsSummary(st), /以後都不排/);
  assert.equal(learnChoices(art, st).length, 1, '記過的那一類不再問');
  assert.equal(unlearn(st, x.id)?.id, x.id);
  assert.ok(stops(draft({ days: 8 }), st).some((i) => i.c === 'art'), '拿掉那一條就會再排');

  const first = stops(draft(), st)[0];
  learn(st, { kind: 'place', key: first.id, n: first.n }, '測試');
  assert.ok(banned(first, st));
  assert.ok(stops(draft({ days: 14 }), st).every((i) => i.id !== first.id));

  const famous = stops(draft({ days: 8 }), st).find((i) => i.f === 'famous') as Stop;
  const food = learnChoices(famous, st).find((c) => c.kind === 'food');
  assert.ok(food);
  learn(st, food, '測試');
  assert.ok(stops(draft({ days: 8 }), st).every((i) => i.f !== 'famous'));
  const only: Settings = { ...defaultSettings(), food: { street: 0, local: 2, famous: 0, fine: 0 } };
  const local = stops(draft(), only).find((i) => i.f === 'local') as Stop;
  assert.ok(!learnChoices(local, only).some((c) => c.kind === 'food'), '只剩一種還在吃的，不給記成不排');
  assert.deepEqual(learnChoices({ ...first, mine: true }, defaultSettings()), [], '自己加的站沒有東西可以記');
});

test('怕冷：冬天出發少排整段在戶外的站；別的季節不變', () => {
  const st: Settings = { ...defaultSettings(), pace: 'fast' };
  const cold: Settings = { ...st, body: ['cold'] };
  const outdoors = (d: TripDraft, s: Settings) => stops(d, s).filter((i) => i.c === 'nature').length;
  assert.ok(outdoors(draft({ days: 8 }), cold) < outdoors(draft({ days: 8 }), st));
  assert.equal(outdoors(draft({ days: 8, start: '2026-04-10' }), cold), outdoors(draft({ days: 8, start: '2026-04-10' }), st));
});

test('過敏告知卡：沒選就沒有卡；選了的韓文都在卡上，也會交給 AI', () => {
  assert.equal(allergyCard([]), null);
  const card = allergyCard(['花生', '蝦蟹']);
  assert.ok(card?.kr.includes('땅콩') && card.kr.includes('새우'));
  assert.ok(card?.zh.includes('花生、蝦蟹'));
  const st: Settings = { ...defaultSettings(), allergy: ['花生'], avoid: ['內臟'], meh: ['辣'], walk: 'less' };
  const t = generate(draft({ tweaks: ['elder'] }), st);
  const first = allItems(t)[0].it;
  learn(st, { kind: 'cat', key: 'kpop', n: '追星' }, '測試');
  const prompt = aiPrompt('多排一點吃的', t, st, []);
  assert.match(prompt, /過敏：花生/);
  assert.match(prompt, /絕對不吃內臟/);
  assert.match(prompt, /不愛吃辣/);
  assert.match(prompt, /這趟特別的地方：帶長輩/);
  assert.ok(!prompt.includes('K-pop 周邊店巡禮'), '說過不排的那一類不會出現在候選裡');
  assert.ok(prompt.includes(first.n));
});
