// 給人看的選項文字。「我」和「開一趟」共用，改一個地方兩邊都會變。
import type { Body, Pace, Tweak, Walk } from './types';

/** 一天能走多少。會改「走路還是搭車」的界線，要少走的半天只排一站 */
export const WALK_TEXT: Record<Walk, { name: string; note: string }> = {
  less: { name: '少走一點', note: '站和站之間超過 500 公尺就搭車，半天只排一站，優先排輕鬆的' },
  normal: { name: '普通', note: '1 公里內用走的' },
  lots: { name: '很能走', note: '2 公里內都用走的' },
};
export const WALKS = Object.keys(WALK_TEXT) as Walk[];

/** 身體上要避開的 */
export const BODY_TEXT: Record<Body, string> = {
  stairs: '不爬長階梯和陡坡',
  heat: '怕熱',
  cold: '怕冷',
};
export const BODY_NOTE: Record<Body, string> = {
  stairs: '標了坡多或階梯多的站不排。這個標記是粗略標的，只標了幾個最明顯的。',
  heat: '6 到 9 月出發的話，少排整段在戶外的站。只看月份，不是天氣預報。',
  cold: '12 到 2 月出發的話，少排整段在戶外的站。只看月份，不是天氣預報。',
};
export const BODIES = Object.keys(BODY_TEXT) as Body[];

/** 這趟臨時調整。note 寫的是這趟實際會改成什麼 */
export const TWEAK_TEXT: Record<Tweak, { name: string; note: string }> = {
  elder: { name: '帶長輩', note: '少走路，不排坡多階梯多的站，不會排到最滿' },
  easy: { name: '想輕鬆一點', note: '一天排得比平常鬆一級' },
  save: { name: '想省一點', note: '晚餐不排精緻餐廳、少排名店；花費改用便宜住宿、一天吃喝 NT$ 1,000 來估' },
  treat: { name: '有要慶祝的事', note: '中間挑一天，晚餐排精緻餐廳' },
};
export const TWEAKS = Object.keys(TWEAK_TEXT) as Tweak[];

/** 節奏。不用「大站／小站」這種要先學才懂的詞，直接講一天會排多少 */
export const PACE_TEXT: Record<Pace, { name: string; note: string; example: string }> = {
  slow: { name: '輕鬆', note: '一天只排一個主要景點，下午空著', example: '上午景福宮，下午回去休息，晚上吃飯' },
  mid: { name: '剛好', note: '一天兩個主要景點，每三天有一天排得很鬆', example: '上午景福宮，下午逛仁寺洞，晚上吃飯' },
  fast: { name: '排滿', note: '一天兩個主要景點，空檔再加順路的小地方', example: '上午景福宮加北村，下午仁寺洞加益善洞，晚上吃飯再逛市場' },
};
export const PACES = Object.keys(PACE_TEXT) as Pace[];

/** 更細的興趣。現在的首爾資料沒有分到這麼細，所以只先記著，接上 AI 後才會照這個排 */
export const INTEREST_TAGS = [
  '傳統市場', '韓服體驗', '汗蒸幕', '韓劇場景', '美妝保養', '文具雜貨', '選物店', '看夜景',
  '爬山健行', '看展覽', '看表演', '拍照景點', '帶小孩', '帶長輩', '下雨也能去',
] as const;
