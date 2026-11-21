# Overnight 報告

分支：`overnight-20261121-2040`（從 `swiftui` 開出來）
任務：把蘿蔔旅行從 Expo 轉成 SwiftUI，修到 GitHub Actions 上編得過、UI 測試全綠，看截圖修畫面問題，更新文件。

## 早上摘要

**6 項全部完成。** SwiftUI 版在 GitHub 上編得過，30 條規則測試和 3 支 UI 測試都綠，截圖逐張看過。

每項一句話：

1. 編譯通過：整個 app（約 8,500 行 Swift）第一次編譯就過，沒有改任何畫面的程式。
2. 規則測試：`ios/RadishCore` 的 30 條全過，跟 `mobile/tests` 一條對一條。
3. UI 測試：`ios/RadishUITests/FlowUITests.swift` 三支全過。走的是：從空白填表單開一趟、看操作說明、拔一站、開單站的卡、用講的改行程講一句、看地圖、開「更多」、逛行前四段與旅行和我、關掉重開確認行程還在。紅過兩輪，都是測試等待時機的問題，app 本身沒改。
4. 截圖：開一趟、這趟、操作說明、拔蘿蔔、單站卡、對話、地圖、行前花費、我，都看過，沒有版面跑掉或字被切的地方。只改了一處：地圖上的路線虛線從方塊改成圓點（`ios/Radish/Components/DayMap.swift`）。
5. 說明文件：`ios/README.md`。
6. 交接：`HANDOFF.md` 加了第 13 節，原本的內容沒動。

沒解決、要你決定的事在下面「待確認」，共 5 件，最要緊的是前 3 件。

早上建議先看：

- GitHub 上這個分支最新一次「iOS check」，下載 `radish-ui-screenshots`，看那 20 幾張截圖順不順眼。
- 拔蘿蔔那張和操作說明那張，這兩個是全螢幕蓋上去的，最可能跟你印象中的手感不一樣。
- 想親手點：下載 `radish-sim-app` 丟上 Limrun。我沒有開 Limrun（要錢）。

沒在真機上跑過。震動、通知、定位、分享、相簿挑照片，模擬器的自動測試都沒碰到。

分支：`overnight-20261121-2040`（從 `swiftui` 開的，`swiftui` 停在畫面剛搬完那一版）

滿意，併回 `swiftui`：

```
git checkout swiftui && git merge --ff-only overnight-20261121-2040 && git push
```

不要，整支丟掉：

```
git checkout swiftui && git branch -D overnight-20261121-2040 && git push origin --delete overnight-20261121-2040
```

## 任務清單

- [x] 1. app 在 CI 上編譯通過。完成標準：macOS 那一關的紀錄出現 `BUILD SUCCEEDED`（或測試有開始跑），沒有 `error:`。
- [x] 2. 規則引擎測試維持全過。完成標準：Linux 那一關 `Executed 30 tests, with 0 failures`。
- [x] 3. 三支 UI 測試全綠。完成標準：紀錄出現 `TEST SUCCEEDED`，`FlowUITests` 三條都過。
- [x] 4. 看截圖修畫面問題。完成標準：開一趟、這趟、單站卡、對話、地圖、更多、行前四段、旅行、我，每張截圖都看過；版面跑掉、字被切、東西疊在一起的地方修掉，修完那一輪 CI 仍全綠。
- [x] 5. 寫 `ios/README.md`。完成標準：寫清楚怎麼看 CI 結果、怎麼拿截圖、檔案在哪、哪些還沒在真機驗過。
- [x] 6. 把這一輪的做法記進 `HANDOFF.md` 最後面（只加一節，不改原本的內容）。完成標準：新會話讀那一節就知道 SwiftUI 版現況。

## 待確認（需要多米決定的事）

1. **`CLAUDE.md` 要不要改。** 現在寫的是「`mobile/`：Expo app」和四條 mobile 的規矩。我沒有動它（改核心設定檔要先給你看）。建議把 `mobile/` 那一行改成「`ios/`：SwiftUI app，怎麼看結果看 `ios/README.md`；`mobile/` 是舊的 Expo 版，只當對照」，四條規矩換成 `ios/README.md`「規矩」那五條。
2. **`mobile/` 什麼時候刪。** 我留著沒動。建議等你在真機上看過 SwiftUI 版再刪。
3. **要不要接 TestFlight。** 要的話需要把簽章憑證和 App Store Connect 金鑰放進這個 repo 的 Secrets，還要在 Apple 後台登記 `org.domyweb.radish`。人蔘修煉那條 CI 可以照抄。
4. **「用講的改行程」的 AI。** Expo 版測試時是接這台電腦的 claude cli，SwiftUI 版沒有這條路，現在只聽得懂本機那幾句。要測 AI 得先有一個後端網址。
5. **地圖標記的韓文名稱。** SwiftUI 的地圖標記只放得下一行字，現在只顯示中文站名。要韓文的話得改成自己畫的標記，我沒做。

## 卡住的項目

## 執行紀錄

- 20:40 開分支 `overnight-20261121-2040`。開跑前的狀態：規則引擎 30 條測試在 CI 全過；畫面全部搬完（約 8,500 行 Swift）但整個 app 還沒編過；檢查線加上 `overnight-**` 分支。
- 21:00 第 1、2 項過：第三輪 CI（c8ca72b）整個 app 第一次編譯就過，沒有 error；規則引擎 30 條測試全過。三支 UI 測試紅，原因是操作說明蓋住畫面時測試去找「第 1 天」分頁，改測試先關操作說明。
- 21:15 第四輪 CI（eda142f）：三支 UI 測試過一支。另外兩支紅在測試自己：拔蘿蔔動畫已經自己關了還去點它；操作說明正在消失時去查它。改成等動畫自己關、關掉說明後不回頭查。
- 21:35 第 3 項過：第五輪 CI（a79e7b9）`TEST SUCCEEDED`，三支全綠，規則測試 30 條全過。
- 21:40 第 4 項過：截圖逐張看過，只把地圖路線虛線改成圓頭。
- 21:45 第 5、6 項過：`ios/README.md` 寫好；`HANDOFF.md` 加第 13 節。
