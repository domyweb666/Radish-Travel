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

const out = {
  dataChecked: S.DATA_CHECKED,
  area: S.AREA,
  adj: S.ADJ,
  hotel: S.HOTEL,
  places: S.PLACES,
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
console.log('[export-seoul] places:', S.PLACES.length);
