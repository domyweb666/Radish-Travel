# 蘿蔔旅行

AI 行程規劃 iPhone app。第一版只做首爾。開工依據是 `HANDOFF.md`，產品定稿在 `.vibe/產品定稿.md`，UIUX 設計檔在 `.uiux/`。

- `mobile/`：Expo app（React Native）。怎麼跑、怎麼檢查看 `mobile/README.md`。
- `prototype/index.html`：手感原型第三版，單檔。GitHub Pages 用，不要改。
- `docs/`：研究與分析。

## mobile/ 的規矩（來自 @domy/design 的 README）

1. 畫面只能用 `@domy/design` 的元件、`T` 和 `useDomy().c`，不准寫色碼、字級、圓角、間距數字。
2. 缺元件就先在 `mobile/src/components/` 用代號組一個本地元件。兩款以上的 App 都要用，才搬進套件。
3. App 的資料、流程、業務邏輯不准放進套件。
4. commit 前在 `mobile/` 跑 `npm run verify`。真的只用一次的數值，在那一行寫 `// domy-ignore: 原因`。

## 產品鐵則（HANDOFF 第 6 節）

- 不掉資料：行程存在手機裡，沒網路也看得到全部。會改行程的動作都要能復原（走 `store.tsx` 的 `act(..., { undoable: true })`）。
- 不騙人：估的寫估的，AI 加的寫 AI 加的，沒核對的不講成確定的事。
- 不做成癮機制：沒有連續天數、稀有蘿蔔、排行榜。
- 排序沒有私心。

## 用詞

照 `.uiux/05-設計代號/詞彙表-暫定.md`。整趟叫「這趟」，單一個點叫「站」，分「大站／小站」。
