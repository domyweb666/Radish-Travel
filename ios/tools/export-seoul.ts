// 把 mobile/src/data/seoul.ts 轉成 Swift 那邊讀的 JSON。資料改了就重跑：
//   cd mobile && node --import tsx ../ios/tools/export-seoul.ts
import { writeFileSync } from 'node:fs';
import * as S from '../../mobile/src/data/seoul';

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
  stay: S.STAY,
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
