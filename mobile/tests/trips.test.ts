import assert from 'node:assert/strict';
import { test } from 'node:test';
import { albumHtml, sketchSvg } from '../album/albumHtml';
import { allItems, defaultSettings, generate } from '../src/domain/plan';
import { remindOn, remindersOf, unbookedOf } from '../src/domain/remind';
import { archiveTrip, basketItem, openShelved, shelveCurrent, visitedOf } from '../src/domain/tripActions';
import type { AppState } from '../src/domain/types';

const state = (): AppState => ({
  settings: defaultSettings(),
  trip: generate({ city: 'seoul', start: '2026-12-01', days: 5, arrive: 'pm', leave: 'pm', people: 2 }, defaultSettings()),
  shelf: [],
  seeds: [],
  pool: [],
  checks: { passport: true, b_x1: true },
  chat: [{ r: 'me', t: '第 2 天輕鬆一點' }],
  baskets: [],
  settingsDirty: false,
  aiConsent: false,
  guideSeen: false,
  remind: false,
  debugDay: 2,
});

test('開新的一趟：現在這趟原樣放到「其他排好的」，切回來一樣不少', () => {
  const d = state();
  const before = JSON.stringify(d.trip);
  shelveCurrent(d);
  assert.equal(d.trip, null);
  assert.equal(d.shelf.length, 1);
  assert.deepEqual(d.chat, []);
  assert.equal(d.debugDay, null);
  assert.deepEqual(d.checks, { passport: true }, '行前檢查表留著，要先訂的勾選跟著那一趟走');

  // 排第二趟，再切回第一趟
  d.trip = generate({ city: 'seoul', start: '2027-03-10', days: 3, arrive: 'am', leave: 'eve', people: 1 }, d.settings);
  const second = JSON.stringify(d.trip);
  openShelved(d, d.shelf[0].id);
  assert.equal(JSON.stringify(d.trip), before);
  assert.equal(d.chat.length, 1);
  assert.equal(d.debugDay, 2);
  assert.equal(d.checks.b_x1, true);
  assert.equal(d.shelf.length, 1);
  assert.equal(JSON.stringify(d.shelf[0].trip), second, '第二趟換到架上，沒有不見');
});

test('收起來：去過的站帶著位置、第幾天、那一句和照片進「去過的旅行」', () => {
  const d = state();
  const first = allItems(d.trip!)[0];
  first.it.status = 'pulled';
  first.it.say = '湯很清';
  first.it.photos = ['p1.jpg'];
  assert.equal(visitedOf(d.trip!).length, 1);
  archiveTrip(d);
  assert.equal(d.trip, null);
  const b = d.baskets[0];
  assert.equal(b.start, '2026-12-01');
  assert.equal(b.days, 5);
  assert.equal(b.items[0].say, '湯很清');
  assert.deepEqual(b.items[0].photos, ['p1.jpg']);
  assert.equal(b.items[0].day, first.s.day);
  assert.equal(typeof b.items[0].lat, 'number');
});

test('收起來之後還可以補一句、加照片，別站不受影響', () => {
  const d = state();
  const stops = allItems(d.trip!).slice(0, 2);
  stops.forEach((x) => (x.it.status = 'pulled'));
  stops[0].it.say = '原本那句';
  archiveTrip(d);
  const id = d.baskets[0].id;
  const second = basketItem(d, id, 1)!;
  second.say = '後來補的';
  second.photos = ['p1.jpg'];
  assert.equal(d.baskets[0].items[1].say, '後來補的');
  assert.deepEqual(d.baskets[0].items[1].photos, ['p1.jpg']);
  assert.equal(d.baskets[0].items[0].say, '原本那句');
  assert.equal(basketItem(d, id, 99), undefined);
  assert.equal(basketItem(d, '沒有這趟', 0), undefined);
});

test('地圖網頁：使用者打的字不會變成網頁的程式', () => {
  const html = albumHtml({
    title: '首爾 <5> 天',
    dates: '12/1–12/5',
    stops: [
      { n: '景福宮', kr: '경복궁', day: 1, date: '12/1（二）', say: '</script><script>alert(1)</script>', lat: 37.5796, lng: 126.977, photos: ['data:image/jpeg;base64,AAAA'] },
      { n: '自己加的店', day: 2, photos: [] },
    ],
  });
  assert.ok(!html.includes('<script>alert(1)'), '那一句裡的標籤要被換掉');
  assert.ok(html.includes('首爾 &lt;5&gt; 天'));
  assert.ok(html.includes('第 1 天') && html.includes('第 2 天'));
  assert.ok(html.includes('有 1 站沒有位置資料'));
  assert.equal((html.match(/<article /g) ?? []).length, 2);
  assert.ok(html.includes('integrity="sha256-'), '外部的 Leaflet 要帶完整性雜湊');
});

test('路線圖：有位置的站各一個圓點，沒位置的不畫；一站也畫得出來', () => {
  const svg = sketchSvg([
    { n: 'a', lat: 37.58, lng: 126.98, photos: [] },
    { n: 'b', photos: [] },
    { n: 'c', lat: 37.5, lng: 127.03, photos: [] },
  ]);
  assert.equal((svg.match(/class="pin"/g) ?? []).length, 2);
  assert.ok(!svg.includes('NaN'));
  assert.ok(!sketchSvg([{ n: 'a', lat: 37.58, lng: 126.98, photos: [] }]).includes('NaN'));
  assert.equal(sketchSvg([{ n: 'b', photos: [] }]), '');
});

test('提醒日：出發前七天；不到七天就明天；明天出發或已經出發就不提醒', () => {
  assert.equal(remindOn('2026-12-01', '2026-11-16'), '2026-11-24');
  assert.equal(remindOn('2026-12-01', '2026-11-27'), '2026-11-28');
  assert.equal(remindOn('2026-12-01', '2026-11-30'), null);
  assert.equal(remindOn('2026-12-01', '2026-12-02'), null);
});

test('提醒內容：只列還沒打勾的；全部勾完就沒有提醒；其他排好的那幾趟也算', () => {
  const d = state();
  const need = unbookedOf(d.trip!, d.checks);
  assert.ok(need.length > 0);
  const [r] = remindersOf(d, '2026-11-16');
  assert.equal(r.on, '2026-11-24');
  assert.ok(r.body.includes(`${need.length} 站`));
  assert.ok(r.body.includes(need[0].n));
  d.checks['b_' + need[0].id] = true;
  assert.ok(!remindersOf(d, '2026-11-16')[0]?.body.includes(need[0].n) || need.length === 1);
  need.forEach((x) => (d.checks['b_' + x.id] = true));
  assert.equal(remindersOf(d, '2026-11-16').length, 0);
  const e = state();
  shelveCurrent(e);
  assert.equal(remindersOf(e, '2026-11-16').length, 1);
});
