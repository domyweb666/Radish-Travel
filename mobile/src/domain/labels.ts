// 給人看的選項文字。「我」和「開一趟」共用，改一個地方兩邊都會變。
import type { Pace } from './types';

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
