import assert from 'node:assert/strict';
import { test } from 'node:test';
import { applyOps, localBrain } from '../src/domain/chat';
import { addDays, diffDays, fmtDay, monthGrid, phaseOf } from '../src/domain/dates';
import {
  addOwn, allItems, alternatives, bigCount, cost, dayLegs, dayStops, defaultSettings, generate, moveItem, planText,
  replaceWith, restoreSeed, seedOut, swapParts,
} from '../src/domain/plan';
import type { Seed, TripDraft } from '../src/domain/types';

const draft = (over: Partial<TripDraft> = {}): TripDraft => ({ start: '2026-12-04', days: 5, arrive: 'pm', leave: 'pm', people: 2, ...over });

test('排出來的行程守住機制規則', () => {
  for (const days of [3, 4, 5, 7, 10, 14]) {
    for (const pace of ['slow', 'mid', 'fast'] as const) {
      const st = { ...defaultSettings(), pace };
      const t = generate(draft({ days }), st);
      assert.equal(t.slots.length, days * 3);
      const ids = allItems(t).map((x) => x.it.id);
      assert.equal(new Set(ids).size, ids.length, '同一站不會排兩次');
      for (let d = 1; d <= days; d++) assert.ok(bigCount(t, d) <= 2, `第 ${d} 天大站不超過 2`);
      assert.equal(bigCount(t, 1), 0, '第一天不排大站');
      assert.equal(bigCount(t, days), 0, '最後一天不排大站');
      assert.ok(allItems(t).every((x) => x.it.why.length > 0), '每一站都有為什麼');
    }
  }
});

test('下午到的第一天，上午是在路上', () => {
  const t = generate(draft({ arrive: 'pm' }), defaultSettings());
  assert.equal(t.slots.find((s) => s.day === 1 && s.part === 'am')?.off, true);
  assert.equal(t.slots.find((s) => s.day === 1 && s.part === 'eve')?.off, undefined);
});

test('拿掉的站進下次再來，可以排回原本的時段', () => {
  const t = generate(draft(), defaultSettings());
  const seeds: Seed[] = [];
  const { it, s } = dayStops(t, 2)[0];
  const before = allItems(t).length;
  seedOut(t, seeds, it.id, '測試');
  assert.equal(allItems(t).length, before - 1);
  assert.equal(seeds.length, 1);
  const msg = restoreSeed(t, seeds, seeds[0].id);
  assert.match(msg, new RegExp(`第 ${s.day} 天`));
  assert.equal(allItems(t).length, before);
  assert.equal(seeds.length, 0);
});

test('移動、對調、換一個、自己加', () => {
  const st = defaultSettings();
  const t = generate(draft(), st);
  const { it } = dayStops(t, 2)[0];
  assert.equal(moveItem(t, it.id, 3, 'pm'), null);
  assert.ok(dayStops(t, 3).some((x) => x.it.id === it.id));
  assert.match(moveItem(t, it.id, 1, 'am') ?? '', /在路上/);
  assert.equal(swapParts(t, 2, 'am', 'pm'), null);
  const target = dayStops(t, 3)[0].it;
  const alts = alternatives(t, st, target);
  assert.ok(alts.length > 0);
  assert.equal(replaceWith(t, target.id, alts[0]), null);
  assert.ok(allItems(t).some((x) => x.it.id === alts[0].id));
  const seeds: Seed[] = [];
  assert.match(addOwn(t, seeds, '我想去的店'), /排在第/);
});

test('本機指令聽得懂的那幾種', () => {
  const t = generate(draft(), defaultSettings());
  const seeds: Seed[] = [];
  const a = localBrain('第 2 天上午下午對調', t);
  assert.equal(applyOps(t, seeds, a.ops).changes.length, 1);
  const name = dayStops(t, 3)[0].it.n.replace(/（.*?）/g, '');
  const b = localBrain(`不要${name}`, t);
  const r = applyOps(t, seeds, b.ops);
  assert.equal(r.changes.length, 1);
  assert.equal(seeds.length, 1);
  assert.equal(localBrain('重排', t).regen, true);
  assert.equal(localBrain('今天天氣如何', t).ops.length, 0);
  assert.deepEqual(applyOps(t, seeds, [{ op: 'move', id: 'nope', day: 2, part: 'am' }]).notes, ['找不到那一站']);
});

test('花費與路程算得出數字', () => {
  const st = defaultSettings();
  const t = generate(draft(), st);
  const c = cost(t, st);
  assert.ok(c.total > 0 && Number.isFinite(c.total));
  const legs = dayLegs(t, st, 2);
  assert.equal(legs.length, dayStops(t, 2).length + 1);
  assert.ok(planText(t).includes('第 5 天'));
});

test('日期', () => {
  assert.equal(addDays('2026-12-30', 3), '2027-01-02');
  assert.equal(diffDays('2026-12-04', '2026-12-08'), 4);
  assert.equal(fmtDay('2026-12-04'), '12/4（五）');
  assert.equal(monthGrid(2026, 12).filter(Boolean).length, 31);
  assert.deepEqual(phaseOf('2026-12-04', 5, '2026-11-15', null), { kind: 'plan', daysToGo: 19 });
  assert.deepEqual(phaseOf('2026-12-04', 5, '2026-12-06', null), { kind: 'trip', day: 3 });
  assert.deepEqual(phaseOf('2026-12-04', 5, '2026-12-09', null), { kind: 'done' });
  assert.deepEqual(phaseOf('2026-12-04', 5, '2026-11-15', 2), { kind: 'trip', day: 2 });
});
