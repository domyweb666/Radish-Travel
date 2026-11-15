# 蘿蔔旅行 iOS 版（Expo）

階段 1 的骨架：四個分頁、開一趟的問答、本機儲存、原型那套本機排程規則、首爾範例資料。介面用 `@domy/design`，產品色是蘿蔔橘。AI 和地點查證還沒接。

## 在 iPhone 上跑

1. iPhone 裝 Expo Go（App Store 搜尋 Expo Go）。
2. 電腦上：

```bash
cd mobile
```

```bash
npm install
```

```bash
npm run ios
```

3. 終端機會出現 QR code，用 iPhone 相機掃，會在 Expo Go 裡打開。

`npm run ios` 走 tunnel，手機和電腦不在同一個 Wi-Fi 也連得到。第一次會問要不要裝 `@expo/ngrok`，按 y。

`npm install` 會從 GitHub 抓私人 repo `domyweb666/domy-design`，這台電腦要登入有權限的 GitHub 帳號。

## 在電腦上看

```bash
npm run web
```

網頁版沒有 Apple 地圖、觸覺回饋，彈出卡也不是 iOS 的樣子，只能拿來看版面和流程。

## 檢查

```bash
npm run verify
```

跑三件事：型別、`tests/` 的排程規則與蘿蔔橘對比、畫面裡有沒有寫死的色碼和數字。

```bash
npm run bundle:check
```

把 iOS 版的 JS 打包一次，確認每個模組都找得到。

## 檔案

| 路徑 | 內容 |
|---|---|
| `App.tsx` | 外殼：四個分頁＋懸浮分頁列 |
| `src/theme.ts` | 蘿蔔橘（`createTheme`）和蘿蔔的角色色 |
| `src/data/seoul.ts` | 首爾範例資料，從原型轉出來，全部未核對 |
| `src/domain/plan.ts` | 排程規則、移動對調、路程與花費估算。純函式 |
| `src/domain/chat.ts` | 用講的改行程：本機指令、`applyOps`、給 AI 的提示詞 |
| `src/domain/dates.ts` | 日期、星期、這趟現在在哪個階段 |
| `src/store.tsx` | 狀態、本機儲存、復原（最多 20 步） |
| `src/domain/tripActions.ts` | 整趟的動作：收起來、先放一邊排另一趟、切回來 |
| `src/domain/labels.ts` | 「我」和「開一趟」共用的選項文字 |
| `src/io/photos.ts` | 挑照片、縮小、存進 app 的資料夾 |
| `album/albumHtml.ts` | 把一趟去過的站做成有地圖的網頁檔。不是 app 畫面，所以在 `src` 外 |
| `src/screens/` | 這趟、行前、旅行、我 |
| `src/sheets/` | 單站的卡、用講的改、地圖、自己加一站、一趟去過的 |
| `src/components/` | 本地小元件，全部用 `@domy/design` 的代號組的 |

## 接 AI

`src/domain/chat.ts` 會讀環境變數 `EXPO_PUBLIC_AI_ENDPOINT`。有設的話，「用講的改行程」會把提示詞 POST 到那個網址（`{ "prompt": "..." }`），後端要回 `{ "reply": "...", "ops": [...] }`。沒設就用本機指令。

金鑰放後端，不放 app。這條路寫好了但還沒有後端可以測。

## 還沒做、還沒驗

- 沒在真的 iPhone 上跑過。Apple 地圖元件、觸覺、彈出卡下拉關閉、鍵盤會不會蓋住輸入框，都要在 Expo Go 上看。
- AI 排行程、地點查證、韓文地址：HANDOFF 階段 2。
- 通知（出發前一週、要先訂的）：還沒做，現在只在「行前」分頁最上面提醒。
- 付費：還沒做，要先過 UIUX 閘門 4。
- 蘿蔔是占位的向量圖，還沒換成黏土插圖。
- 2026-11-15 照真機回饋改的這一輪，下面這些只在網頁預覽或測試裡驗過，沒在手機上驗：
  - 拔蘿蔔的那一下（`src/components/PullMoment.tsx`）：動畫的節奏和三段震動的手感。
  - 加照片：相簿選取、縮圖、存檔。網頁預覽不會真的存檔。
  - 把地圖網頁檔分享出去。網頁預覽是直接下載。
- 可以同時排好幾趟，但還沒跟「按趟計價」接起來。付費要先過 UIUX 閘門 4。
- 「行前」的吃與買是先整理的清單，沒有逐條核對、沒有來源，畫面上有標。
- 喜好裡「更細的」和「其他想做的」、住宿名稱，都只是先記著，還不會影響排程。
- 景點照片、招牌菜、平均消費、AI 問答問喜好，要等接上地點查證和 AI 後端。
- 已經收起來的旅行只能看，不能再補一句或加照片。
- 蘿蔔人（`src/components/buddy/`）只在網頁預覽看過，沒在真機上看過順不順。「抓頭」「指向」兩個動作寫好了還沒用到。
- `@domy/design` 裝的是 v1.1.0。本機的 `E:\domy-design` 已經到 v1.4.0 但還沒推上 GitHub；手機端的元件和代號兩版一樣，差別只在桌面版。
- 送 EAS Build 前要在 `app.json` 補 `ios.bundleIdentifier`，並讓 EAS 讀得到私人的 domy-design（給 GitHub token，或把套件改成複製進來）。
