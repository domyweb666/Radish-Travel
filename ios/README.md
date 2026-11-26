# 蘿蔔旅行 iOS 版（SwiftUI）

2026-11-21 從 `mobile/`（Expo）搬過來的。畫面、文字、流程照 Expo 版，規則引擎逐條對照搬成 Swift。`mobile/` 先留著當對照，SwiftUI 版在真機驗過之後再刪。

這台電腦是 Windows，沒有 Mac，也沒有 Swift 編譯器。編譯、測試、截圖全部在 GitHub Actions 上做。

## 怎麼知道現在是好的

推到 `swiftui`、`work/**` 或 `overnight-**` 分支，GitHub Actions 的「iOS check」會跑兩關：

1. **規則引擎測試（Linux）**：`ios/RadishCore` 的 301 條測試，一分鐘左右。
2. **編譯與模擬器截圖（macOS）**：把整個 app 編起來，開 iPhone 模擬器跑 `RadishUITests`，每個畫面截一張圖。
   `FlowUITests` 從空白走一次主流程；`SceneUITests` 用啟動參數直接開到某個狀態（旅途中、回來後、沒網路、句數用完、深色、大字），一個畫面一條。
   場景和假的 AI 在 `Radish/App/UITestScenes.swift`，只有 Debug 版有。

推完之後跑這一行，它會等 CI 跑完，印出錯誤，並把截圖抓回來：

```bash
bash ios/tools/watch-check.sh
```

截圖也可以到 GitHub 那次執行的頁面下載，artifact 名字是 `radish-ui-screenshots`。模擬器版的 app 在 `radish-sim-app`，可以上傳到 Limrun 親手點。

## 資料夾

| 路徑 | 內容 |
|---|---|
| `project.yml` | XcodeGen 的專案定義。Xcode 專案檔不進 git，CI 每次重新產生。加 Swift 檔不用改這裡 |
| `RadishCore/Sources/RadishCore/` | 資料型別和規則：排行程、喜好、花費、提醒、對話、地圖網頁、核對資料（`SeoulFacts`）、要先訂（`Book`）。只用 Foundation |
| `RadishCore/Sources/RadishCore/Resources/seoul.json` | 首爾資料包，從 `mobile/src/data/seoul.ts` 轉出來的，裡面的須知和票價沒核對。p52 到 p56（路邊和市場的店）是 SwiftUI 版才加的，`export-seoul.ts` 轉的時候接在最後面 |
| `RadishCore/Sources/RadishCore/Resources/seoul-checked.json` | 首爾的核對資料，疊在 `seoul.json` 上面，看下面「核對資料」 |
| `RadishCore/Tests/` | 規則的測試。從 `mobile/tests/` 搬來的，加上 SwiftUI 版之後才有的（跟 AI 講、同意、句數、復原、開一趟寫的那句、核對資料、休館、要先訂、長行程） |
| `Radish/App/` | 外殼、三個分頁（這趟／問 AI／旅行）、推進頁總管（`Nav`）、狀態儲存（`AppStore`）、彈出卡總管（`Sheets`） |
| `Radish/Kit/` | Domy Design 的 SwiftUI 元件、蘿蔔橘（`Theme.swift`）、圖示、蘿蔔和蘿蔔人 |
| `Radish/Screens/` | 這趟、問 AI（`AskScreen`）、旅行、開一趟；推進頁：檢查這趟、須知、花費（`TripPages`）、平常的我（`MeScreen`）、一站（`StopScreen`）、去過的那一趟（`VisitedScreen`） |
| `Radish/Sheets/` | 半頁：剛剛那一則、路線、附近、移到別的時段、自己加一站、更多、行程設定 |
| `Radish/Components/` | 講的那一列（`TalkBar`）、剛排好和回來後的卡（`TripCards`）、表單、月曆、拔蘿蔔動畫、給司機看、過敏告知卡、一站頁的開放／怎麼訂／來源（`StopFacts`） |
| `Radish/IO/` | 照片、本機通知、外部地圖、分享 |
| `RadishUITests/` | 截圖的測試：主流程 `FlowUITests`、一個畫面一條的 `SceneUITests` |
| `tools/` | 轉資料、檢查寫死數值、等 CI 的腳本；`scan-street-dinner.mjs` 用 node 照搬排行程的規則，數只吃路邊的人有幾個晚上空著 |

`RadishCore` 的原始碼是直接編進 app 的，跟 app 同一個模組。`Package.swift` 只給 Linux 上跑測試用。

## 規矩

1. 畫面只能用 `T`（尺寸、圓角、間距、字級）和 `C`（顏色），不准寫色碼和數字。CI 會跑 `node ios/tools/check-hardcoded.mjs` 擋。真的只用一次的數值，在那一行寫 `// domy-ignore: 原因`。
2. 所有字用 `DomyText`，按鈕用 `DomyButton`，分組用 `DomySection`。缺元件先在 `Radish/Kit/LocalKit.swift` 用代號組一個。
3. 會改行程的動作一律 `store.act(undoable: true)`。
4. 動畫曲線和震動照 `Radish/Kit/Motion.swift` 那張動作代號表，不准自己寫 `.easeInOut(duration:)`。原則在 `手感指南.md`。會變的數字用 `DomyText(..., numeric: true)`。
5. `RadishCore` 只准 `import Foundation`。
6. 首爾資料改了，在 `mobile/` 跑 `node --import tsx ../ios/tools/export-seoul.ts` 重新轉一次。核對資料不從 `mobile/` 來，直接改 `seoul-checked.json`，規則測試會擋格式錯的。

搬的時候講好的寫法在 `PORTING.md`（規則）和 `UI-PORTING.md`（畫面，有 React Native 對 SwiftUI 的對照表）。

## 核對資料（0.5）

`seoul-checked.json` 是 AI 上網核對的結果，2026-11-25 查的，`mobile/` 沒有對應的檔。每一欄的意思在 `SeoulFacts.swift`，查的規矩和來源原文在 `docs/核對原始檔/`（那裡的 `merge.py` 只合併第一版，後來的修正直接改在 JSON 裡，再跑一次會蓋掉）。

**怎麼疊**：`drop` 把 `seoul.json` 的地點拿掉，`add` 接上新的，`facts` 照地點代號查。「挑一間」那種沒指名的拿掉，換成真店，代號是原本的加 a、b、c（`p4` 變 `p4a`、`p4b`、`p4c`，算同一組）。每個地點都有一筆，狀態分 `official`（讀過官方頁）、`second`（二手資料）、`none`（沒查到）。沒查到的欄位留空，不猜；排行程的時候當成有開。以後都不排的舊代號 `p4`，拆出來的每一間都不排。

**休館日和開放時段**：
- 休館看固定星期幾、每月第幾個星期幾、節日、國定假日補休、臨時休館和整修（`closedWhy`）。時段看那天上午、下午、晚上有沒有開，至少待得到一小時半才算（`partClosedWhy`）。「這天要注意」只提醒，不擋（`cautionWhy`）。
- 排行程、換一個、附近會避開不開的那天和時段，路線的建議避開不開的時段。從下次再來排回來，有別的時段就換過去；都不開才照放，而且講出來。
- 移站、改行程設定、跟 AI 講了改，還是放得進去，改完會講哪一站不開。AI 的提示詞裡只有休館日，沒有開放時段。
- 國定假日表只到 2028 年底。

**同組一趟一間**：晚餐照喜好挑，這一帶沒有就找全首爾，再沒有就換一類，都沒有才排同組沒去過的另一間。超過七天的行程，白天整個時段挑不到才這樣放寬，而且不放吃的。同一間不會排兩次。吃的白天一天最多一站，加晚餐最多兩站。近郊那天沒有一站能去，就照平常的一天排。

**只吃路邊**：路邊和市場的店一共九間（2026-11-26 補了明洞路邊攤、鍾路 3 街布帳馬車街、新堂洞炒年糕街、首爾中央市場、芳荑市場，全是二手資料）。同一間一趟只排一次，白天也會排掉，所以五天以內每晚都有，六天以上還是會有晚上空著。跑 `node ios/tools/scan-street-dinner.mjs` 看現在的數字。

**要先訂**：
- `needsBook` 看現在的資料，舊存檔裡的標記不算；自己加的、AI 加的才看那一站自己的。
- 知道幾點開賣的，開賣前 15 分鐘一則；只知道哪天開賣的，那天早上 9 點。免費取消的最後一天早上 9 點再一則，同一天已經有開賣那則就不重複。其他還沒打勾的併成一則，出發前七天。
- 出發之後開賣和取消那兩種還在，整趟走完才停。打勾的、去過的不提醒，最多排 40 則，沒有聲音。
- 資料寫的是韓國時間，畫面換成台灣時間並寫明。

**須知跟著日期走**：檢查這趟的電子入境卡和 K-ETA 照這趟到的那天換字（`dated`）。K-ETA 免申請只公告到 2026-12-31，之後到的會變成「再查一次」，字用警告色。一站的須知用核對過的那句；資料包原本那句還要講的，另外放一列標未核對。

## 跟 Expo 版不一樣的地方

- 沒有網頁預覽，也不能用 Expo Go 掃碼。要看畫面就看 CI 截圖，或把模擬器版丟上 Limrun。
- 存檔從 AsyncStorage 換成 app 資料夾裡的一個 JSON 檔。兩版的資料不互通。存檔讀不出來時不會蓋掉，會改名留著。
- 「用講的改行程」有三種接 AI 的方法，都接了就照這個順序用：連自己電腦的 Claude CLI（平常的我裡掃 QR code，電腦端在 `tools/claude-bridge/`）、平常的我裡填的 Claude API 金鑰（存在鑰匙圈）、自己的後端（建置設定 `RADISH_AI_ENDPOINT`，要填完整網址；後端還沒有，現在是空的）。三種都沒接，就只聽得懂手機自己的那幾句。第一次送到一個地方會先問。
- 挑照片改用系統的相簿選擇器，不用問相簿權限。
- 地圖上點標記只看得到中文站名，韓文名稱沒有顯示（SwiftUI 的標記放不了第二行）。
- 輸入框的字數上限是打完才截掉，超過的那個字可能會閃一下。

## 還沒驗的

- 多米的手機上還沒一項一項驗過。震動、拔蘿蔔的節奏、通知會不會跳出來、定位、分享網頁檔，模擬器都驗不到。
- TestFlight 走得通（推 `tf-N` 標籤才出版，`.github/workflows/ios.yml`），出到 0.7.0（tf-9，2026-11-27）。
- 真的 AI 沒有在 CI 上打過：UI 測試裡的 AI 全是假的，送出去的請求在手機裡就攔下來了。
- 深色只截三個分頁，加上休館那天的這趟、一站和給司機看（大字），而且是用測試參數 `-uitest-dark` 指定深色；跟著系統切深淺、其他畫面的深色都還沒看過。
- 大字級只截這趟、檢查這趟、移到別的時段，加上休館那天的這趟、一站和給司機看。
- 過敏告知卡的韓文還沒核對。
- 首爾的核對資料是 AI 讀網頁查的，沒有人到現場或打電話確認過。愛寶樂園、清溪川、樂天世界、Seoul Sky 的官網機器讀不到。
