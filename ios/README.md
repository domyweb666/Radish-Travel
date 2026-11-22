# 蘿蔔旅行 iOS 版（SwiftUI）

2026-11-21 從 `mobile/`（Expo）搬過來的。畫面、文字、流程照 Expo 版，規則引擎逐條對照搬成 Swift。`mobile/` 先留著當對照，SwiftUI 版在真機驗過之後再刪。

這台電腦是 Windows，沒有 Mac，也沒有 Swift 編譯器。編譯、測試、截圖全部在 GitHub Actions 上做。

## 怎麼知道現在是好的

推到 `swiftui`、`work/**` 或 `overnight-**` 分支，GitHub Actions 的「iOS check」會跑兩關：

1. **規則引擎測試（Linux）**：`ios/RadishCore` 的 30 條測試，一分鐘左右。
2. **編譯與模擬器截圖（macOS）**：把整個 app 編起來，開 iPhone 模擬器跑 `RadishUITests`，每個畫面截一張圖。大約十分鐘。

推完之後跑這一行，它會等 CI 跑完，印出錯誤，並把截圖抓回來：

```bash
bash ios/tools/watch-check.sh
```

截圖也可以到 GitHub 那次執行的頁面下載，artifact 名字是 `radish-ui-screenshots`。模擬器版的 app 在 `radish-sim-app`，可以上傳到 Limrun 親手點。

## 資料夾

| 路徑 | 內容 |
|---|---|
| `project.yml` | XcodeGen 的專案定義。Xcode 專案檔不進 git，CI 每次重新產生。加 Swift 檔不用改這裡 |
| `RadishCore/Sources/RadishCore/` | 資料型別和規則：排行程、喜好、花費、提醒、對話、地圖網頁。只用 Foundation |
| `RadishCore/Sources/RadishCore/Resources/seoul.json` | 首爾資料包，從 `mobile/src/data/seoul.ts` 轉出來的，全部未核對 |
| `RadishCore/Tests/` | 規則的測試，跟 `mobile/tests/` 一條對一條 |
| `Radish/App/` | 外殼、三個分頁（這趟／問 AI／旅行）、推進頁總管（`Nav`）、狀態儲存（`AppStore`）、彈出卡總管（`Sheets`） |
| `Radish/Kit/` | Domy Design 的 SwiftUI 元件、蘿蔔橘（`Theme.swift`）、圖示、蘿蔔和蘿蔔人 |
| `Radish/Screens/` | 這趟、問 AI（`AskScreen`）、旅行、開一趟；推進頁：檢查這趟、須知、花費（`TripPages`）、平常的我（`MeScreen`）、一站（`StopScreen`）、去過的那一趟（`VisitedScreen`） |
| `Radish/Sheets/` | 半頁：剛剛那一則、路線、附近、移到別的時段、自己加一站、更多、行程設定 |
| `Radish/Components/` | 講的那一列（`TalkBar`）、剛排好和回來後的卡（`TripCards`）、表單、月曆、拔蘿蔔動畫、給司機看、過敏告知卡 |
| `Radish/IO/` | 照片、本機通知、外部地圖、分享 |
| `RadishUITests/` | 走主流程並截圖的測試 |
| `tools/` | 轉資料、檢查寫死數值、等 CI 的腳本 |

`RadishCore` 的原始碼是直接編進 app 的，跟 app 同一個模組。`Package.swift` 只給 Linux 上跑測試用。

## 規矩

1. 畫面只能用 `T`（尺寸、圓角、間距、字級）和 `C`（顏色），不准寫色碼和數字。CI 會跑 `node ios/tools/check-hardcoded.mjs` 擋。真的只用一次的數值，在那一行寫 `// domy-ignore: 原因`。
2. 所有字用 `DomyText`，按鈕用 `DomyButton`，分組用 `DomySection`。缺元件先在 `Radish/Kit/LocalKit.swift` 用代號組一個。
3. 會改行程的動作一律 `store.act(undoable: true)`。
4. 動畫曲線和震動照 `Radish/Kit/Motion.swift` 那張動作代號表，不准自己寫 `.easeInOut(duration:)`。原則在 `手感指南.md`。會變的數字用 `DomyText(..., numeric: true)`。
5. `RadishCore` 只准 `import Foundation`。
6. 首爾資料改了，在 `mobile/` 跑 `node --import tsx ../ios/tools/export-seoul.ts` 重新轉一次。

搬的時候講好的寫法在 `PORTING.md`（規則）和 `UI-PORTING.md`（畫面，有 React Native 對 SwiftUI 的對照表）。

## 跟 Expo 版不一樣的地方

- 沒有網頁預覽，也不能用 Expo Go 掃碼。要看畫面就看 CI 截圖，或把模擬器版丟上 Limrun。
- 存檔從 AsyncStorage 換成 app 資料夾裡的一個 JSON 檔。兩版的資料不互通。存檔讀不出來時不會蓋掉，會改名留著。
- 「用講的改行程」的 AI 網址寫在建置設定 `RADISH_AI_ENDPOINT`，要填完整網址。Expo 版那條「開發伺服器轉接這台電腦的 claude cli」沒有搬，所以現在只有本機指令那幾句。
- 挑照片改用系統的相簿選擇器，不用問相簿權限。
- 地圖上點標記只看得到中文站名，韓文名稱沒有顯示（SwiftUI 的標記放不了第二行）。
- 輸入框的字數上限是打完才截掉，超過的那個字可能會閃一下。

## 還沒驗的

- 沒在真的 iPhone 上跑過。震動、拔蘿蔔的節奏、通知會不會跳出來、定位、分享網頁檔，模擬器都驗不到。
- 要裝到手機得走 TestFlight。工作流寫好了（`.github/workflows/ios.yml`），還差三件只有多米能做的事，步驟在 `ios/ci/README.md`。這條線還沒真的跑過。
- 深色模式沒截圖看過。
- 過敏告知卡的韓文、首爾資料，跟 Expo 版一樣都還沒核對。
