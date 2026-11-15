import assert from 'node:assert/strict';
import { test } from 'node:test';
import { albumHtml, sketchSvg } from '../album/albumHtml';
import { allItems, defaultSettings, generate } from '../src/domain/plan';
import { archiveTrip, openShelved, shelveCurrent, visitedOf } from '../src/domain/tripActions';
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
