import assert from 'node:assert/strict';
import { test } from 'node:test';
import { defaultSettings, draftOf, generate } from '../src/domain/plan';
import { addSpend, ownOf, parseKrw, parseRate, removeSpend, spendTotal, toTwd } from '../src/domain/spend';

const trip = () => generate({ city: 'seoul', start: '2026-12-01', days: 4, arrive: 'pm', leave: 'pm', people: 2 }, defaultSettings());

test('花費：打的字換成數字；亂打、空的、0 都不算', () => {
  assert.equal(parseKrw('12,000'), 12000);
  assert.equal(parseKrw(''), 0);
  assert.equal(parseKrw('abc'), 0);
  assert.equal(parseRate('23.5'), 23.5);
  assert.equal(parseRate(''), undefined);
  assert.equal(parseRate('0'), undefined);
  assert.equal(parseRate('9999'), undefined);
});

test('花費：沒填匯率不換台幣；填了照填的算', () => {
  const t = trip();
  addSpend(t, 12000, ' 煎餅 ', 2);
  addSpend(t, 8000, '');
  assert.equal(addSpend(t, 0, '沒金額'), undefined);
  assert.deepEqual(spendTotal(t), { count: 2, krw: 20000, twd: null });
  assert.equal(toTwd(12000, undefined), null);
  t.rate = 23;
  assert.equal(spendTotal(t).twd, 460);
  assert.equal(t.spend?.[1].note, '煎餅');
  assert.equal(t.spend?.[1].day, 2);
  assert.equal(t.spend?.[0].note, undefined);
});

test('花費：刪一筆只少那一筆；重排行程之後紀錄、匯率、機票都還在', () => {
  const t = trip();
  t.flight = 12000;
  t.rate = 23;
  addSpend(t, 5000, 'A');
  const b = addSpend(t, 7000, 'B');
  assert.equal(removeSpend(t, b!.id)?.note, 'B');
  assert.equal(removeSpend(t, 'nope'), undefined);
  assert.equal(spendTotal(t).krw, 5000);
  const again = { ...generate(draftOf(t), defaultSettings()), ...ownOf(t) };
  assert.equal(again.flight, 12000);
  assert.equal(again.rate, 23);
  assert.equal(again.spend?.length, 1);
});
