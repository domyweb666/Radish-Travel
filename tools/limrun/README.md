# 用 Limrun 雲端模擬器跑蘿蔔旅行

沒有 Mac 時拿來驗功能。模擬器按分鐘計費，跑完一定要關。

做法：把 Expo Go 的模擬器版裝上雲端模擬器，再用開發伺服器的 tunnel 網址打開 app。不用先編譯。

## 一次性的準備

1. 這個資料夾裡裝 SDK：`npm i @limrun/api`（不要 commit `node_modules`）。
2. 金鑰放在 `~/.lim/config.yaml` 的 `api-key:`，或環境變數 `LIM_API_KEY`。
3. 下載 Expo Go 模擬器版。網址從 `https://exp.host/--/api/v2/versions` 的 `sdkVersions["58.0.0"].iosClientUrl` 拿。
   解開後整個資料夾要叫 `Expo Go.app`，再壓成 `../expogo/ExpoGo.zip`（相對於這個資料夾）。
4. `node up.mjs upload` 上傳。這一步不計模擬器時間。

## 每次跑

1. 在 `mobile/` 開著 `npm run ios`（tunnel）。
2. 拿 tunnel 網址：`curl -H "expo-platform: ios" http://localhost:8081/` 回傳的 `extra.expoClient.hostUri`。
3. 把 `steps-start-and-pull.json` 裡的 `exp://…` 換成那個網址。
4. `node up.mjs boot`，接著 `node run.mjs "$(cat steps-start-and-pull.json)"`，最後 `node up.mjs down`。
5. `node up.mjs list` 確認自己開的那台是 terminated。別人開的不要刪。

`run.mjs` 開頭列了所有步驟的寫法。截圖存在 `shots/`。

## 2026-11-16 實測到的事

- 開機 7 秒，第一次載入 app 約 25 秒。
- 模擬器的相簿裡有內建照片，可以測加照片。
- 同一個字出現在兩個地方時（例如答過的「下午」和選項「下午」），要用 `tapb` 指定是按鈕。
- `typeText` 打英文會亂序（打 Hotel A 變成 The AH），文字輸入的內容不能靠它驗。
- 測不到震動。
