// 把 mobile/src/data/seoul.ts 轉成 Swift 那邊讀的 JSON。資料改了就重跑：
//   cd mobile && node --import tsx ../ios/tools/export-seoul.ts
import { writeFileSync } from 'node:fs';
import * as S from '../../mobile/src/data/seoul';

// 住宿偏好（QC-0013 #105）是 SwiftUI 版才改的：名稱改成選項上的字、補一句住哪一類、多一種五星級飯店。
// mobile/ 的 STAY 沒動，轉的時候在這裡疊上去，重轉才不會把 lux 弄丟（少了 lux，app 一讀到就當掉）。
// 一晚多少都是粗估，沒核對。
const STAY = {
  cheap: { ...S.STAY.cheap, what: '青旅、民宿' },
  mid: { ...S.STAY.mid, name: '一般', what: '商務旅館' },
  nice: { ...S.STAY.nice, name: '舒服一點', what: '四星' },
  lux: { name: '五星級飯店', perNight: 12000 },
};

// 路邊和市場的店（overnight 第 4 項）也是 SwiftUI 版才加的：只吃路邊的人晚上常空著，補五間晚上有開的。
// mobile/ 沒有，接在最後面，重轉才不會弄丟。開放時間、來源在 seoul-checked.json，這裡只有位置和種類。
const PLACES_IOS = [
  { id: 'p52', n: '明洞路邊攤', kr: '명동 노점', a: 'C', s: 'S', c: 'eat', lat: 37.5638, lng: 126.985, f: 'street', ic: 'eat' },
  { id: 'p53', n: '鍾路 3 街布帳馬車街', kr: '종로3가 포장마차 거리', a: 'B', s: 'S', c: 'eat', lat: 37.5704, lng: 126.9923, f: 'street', ic: 'eat' },
  { id: 'p54', n: '新堂洞炒年糕街', kr: '신당동 떡볶이 골목', a: 'I', s: 'S', c: 'eat', lat: 37.563, lng: 127.0147, f: 'street', ic: 'eat' },
  { id: 'p55', n: '首爾中央市場（新堂洞）', kr: '서울중앙시장', a: 'I', s: 'S', c: 'eat', lat: 37.567, lng: 127.0197, f: 'street', ic: 'market' },
  { id: 'p56', n: '芳荑市場', kr: '방이시장', a: 'F', s: 'S', c: 'eat', lat: 37.511, lng: 127.1157, f: 'street', ic: 'market' },
];

const out = {
  dataChecked: S.DATA_CHECKED,
  area: S.AREA,
  adj: S.ADJ,
  hotel: S.HOTEL,
  places: [...S.PLACES, ...PLACES_IOS],
  cat: S.CAT,
  food: S.FOOD,
  flv: S.FLV,
  avoid: S.AVOID,
  meh: S.MEH,
  allergens: S.ALLERGENS,
  purpose: S.PURPOSE,
  part: S.PART,
  pullLines: S.PULL_LINES,
  stay: STAY,
  taboo: S.TABOO,
  tabooLevel: S.TABOO_LEVEL,
  diff: S.DIFF,
  checklist: S.CHECKLIST,
  noBring: S.NO_BRING,
  sos: S.SOS,
  eats: S.EATS,
  dishes: S.DISHES,
  gifts: S.GIFTS,
  giftRules: S.GIFT_RULES,
};
const to = new URL('../RadishCore/Sources/RadishCore/Resources/seoul.json', import.meta.url);
writeFileSync(to, JSON.stringify(out, null, 1) + '\n');
console.log('[export-seoul] places:', out.places.length);
