# Handoff: A 版 21 張線框畫完、已 push；下一個對話照線框把 SwiftUI app 做出來

> 產出時間：2026-11-23 02:18
> 前一會話的最後狀態，給下一個會話接續用
> 注意：repo 根目錄的 `HANDOFF.md` 是產品的開工依據，跟這份會話交接是兩回事。
> 上一份（2026-11-22 23:02，畫 A 版其他畫面之前）在 `.vibe/handoff/archive/2026-11-22-2302.md`。

## ✅ 這次完成了什麼

- 在 Design 畫布 https://claude.ai/artifact/AZ3L1zCLaZzi1nNuHFEhqo 的「AI 核心介面」頁畫完 A 版其他 18 張（A4-Planned 到 A21-Failed），加四列標題，畫布現在是第 46 版
- 路上分鐘數照 `Plan.swift` 的 `dayLegs` 重算：A1、C1、A3、B3 和 `02-流程-暫定.md` 兩處都改了（第 3 天 138 → 90 分鐘，含從住的地方出發和回去）
- `.uiux/03-線框/方向說明-暫定.md` 補「方向 A 的其他畫面」：每張要看什麼、畫的時候自己定的、查到的；`單手檢查表-暫定.md` 補 A4–A21 十八列
- 線框原始檔和 `canvas.json` 備份在 `.uiux/03-線框/線框/`，跟畫布第 46 版一致
- commit c9fd555 已 push 到 `swiftui`；另一條線還沒 push 的 cadf4ec 一起上去了

## 🚧 還沒做完 / 待決定

- 程式一行都還沒寫。`ios/` 還是四個分頁（這趟／行前／旅行／我），對話還是彈出卡
- 閘門 1、2 都沒過：沒有 3～5 個真人的情境觀察，方向 A 也沒給沒看過的人測。2026-11-23 多米說要在下一個對話「按照這線框做出來」
- 多米還沒答、做的時候會碰到的（`02-流程-暫定.md` 第 10 段）：
  - ❓49 開一趟用先講一句（New-Say）還是表單多一格（New-Form）
  - ❓4、❓8 分頁改三個、叫不叫「問 AI」；線框照三個、照「問 AI」畫
  - ❓48 拔起來那一下的蘿蔔人、下一站卡上那顆蘿蔔留不留；A10 只畫了蘿蔔線條
  - ❓15 手機答得出的先由手機答；A14 的「4 站」和 A19 都靠這條
  - ❓28 句數怎麼算、閘門 4 收費；A20、A21 留了［ ］，`ios/` 還沒有計句數的程式
- 線框沒畫到、做的時候要補的：
  - 另一條線 5c1d537 加了 AI 權限表（`Permit.swift`）：`setTweak` 這種要確認的改動會跳卡，按「套用」才改。A3 半頁要多這個樣子
  - 改這一站的「換一個」「不想去這一站」、行程設定、自己加一站：app 裡現在有，沿用
  - 平常的我的「測試用」那段線框拿掉了，開發時要靠它假裝旅途中，正式版留不留問多米
- A4 寫「你沒講到的，先照一般的排法」，A1 每站卻寫「平常的我：喜歡遊樂設施」，做之前要定一個說法
- repo 的 `CLAUDE.md` 還寫 `mobile/`（Expo）是 app，要不要改是 `OVERNIGHT.md` 待確認第 1 條；改 `ios/` 照 `ios/README.md` 的規矩
- 單手檢查表的「待真機」要等做出來、上 TestFlight 才能填

## 📌 關鍵決策（這次定下來的，下次別再爭論）

- 首頁走方向 A：這一天是主角，最下面一直有一列跟 AI 講；輸入列左邊的小標寫 AI 在看哪裡（第 3 天、今天、某一站），只是標示不能點；「更多」在右上角，跟「平常的我」並排
- 分頁三個：這趟／問 AI／旅行。平常的我改成右上角進去的推進頁；行前拆成檢查這趟、須知（這趟每一天上的常駐入口）和花費（在更多裡）
- 一站、檢查這趟、須知、花費、平常的我、去過的那一趟用推進；移到別的時段、更多、路線、附近、過敏告知卡、剛剛那一則用半頁；拔起來、給司機看用全螢幕
- 路上分鐘數照 `dayLegs` 算，總數含從住的地方出發和回去
- 線框是灰階。做出來用 Domy 元件和蘿蔔橘（`ios/Radish/Kit/`），版面、文字、哪個是主要動作照線框
- B、C 兩個方向的線框留在畫布上當紀錄，不做

## 📂 下個會話最重要的檔案

- `.uiux/03-線框/方向說明-暫定.md`：A 版每張畫什麼、自己定的、查到的
- `.uiux/03-線框/線框/A1-Before.dc.html` 到 `A21-Failed.dc.html`，還有 `Check`、`Notes`、`New-Say`、`New-Form`、`New-Consent`：文字和版面照這些檔，畫面在畫布上看
- `.uiux/02-流程-暫定.md`：第 5-6 段畫面清單 S01–S23 和每個畫面要處理的狀態、第 3 段岔路、9-1 給線框的、9-6 來源標示、9-8 實作、第 10 段 ❓
- `.uiux/03-線框/單手檢查表-暫定.md`：做的時候對照位置和點擊範圍
- `ios/README.md`：規矩（只用 `T`、`C`、Domy 元件、`store.act(undoable: true)`、`Motion.swift`），CI 怎麼看
- `ios/RadishCore/Sources/RadishCore/Permit.swift`、`ios/Radish/Sheets/ChatSheet.swift`：另一條線剛加的權限表和確認卡
- `.uiux/05-設計代號/詞彙表-暫定.md`：用詞，還沒跟這版對齊（`02-流程-暫定.md` 9-4 有要定的詞）
- 記憶 `C:\Users\fcharlie\.claude\projects\E------\memory\radish-travel-ios-2026-11.md`：SwiftUI 的做法和坑（CI、TestFlight、Motion）

## ⏭️ 下一步從哪繼續

> 2026-11-23 第三次更新（6b4c540，CI 全綠）：平常的我可以填 Claude API 金鑰（claude-opus-5-5、effort low、鑰匙圈）；句數 ❓28 先定成「只有走後端才算、第一趟 20 句之後 100 句、AI 有回才算、復原不退」；路線半頁的「這次會改」做完（RouteSuggest.swift，沒接 AI 時手機算）；`ios/tools/claude-bridge` 電腦端轉接 + 平常的我「連電腦的 Claude CLI」掃 QR code（有連就最優先）。❓49 畫了對照圖給多米，Agent 建議 B（表單多一格），等他選。掃 QR 要真機，下一步推 tf-4。
> 2026-11-23 再更新：片 2–6 也做完了（多米說「直接開 subagent，全做」），四個 subagent 各管各的檔，合併後 97b8092、b411d93，CI 全綠、截圖看過。
> 新檔：`Components/TalkBar.swift`（`.talkBar(_:target:)`、`AppStore.talk(_:target:)`）、`Sheets/ReplySheet.swift`、`Screens/AskScreen.swift`、`IO/Network.swift`、`Screens/StopScreen*.swift`、`Sheets/MoveSheet.swift`、`Components/DriverView.swift`、`Sheets/NearbySheet.swift`、`Components/TripCards.swift`、`Screens/VisitedScreen.swift`；刪了 ChatSheet、StopSheet、AlbumSheet、操作說明三步。
> 還沒做：句數用完只有畫面、不會出現（❓28）；路線半頁「AI 的改法換一面」等 AI 回覆格式；回報這則（沒後端）；清單上的站「剛改過／AI 加的」標籤；開一趟（❓49）；S06 從檢查這趟進來的排序。都沒上真機，下一步推 tf-4 給多米。
> 2026-11-23 更新：片 1 做完。外殼在 `ios/Radish/App/Nav.swift`、推進頁在 `Screens/TripPages.swift`；問 AI 分頁暫時是 `ChatSheet(inTab: true)`。這趟標題下的日期那行還是舊寫法，A1 的一行寫法留給片 2 或片 6。下一個從片 2 開始。

1. 先問多米：另一條 SwiftUI 線（5c1d537、cadf4ec 改了 `ChatSheet.swift`、`Chat.swift`、`Permit.swift`）還在跑嗎？還在跑就先講好誰改哪些檔，不要兩條線同時改同一批 `ios/` 檔
2. 讀這份、`方向說明-暫定.md`、`ios/README.md`，再看 `02-流程-暫定.md` 第 5-6 段。設計寫成程式照多米的流程走 VibeRails（9-8：附 `.uiux/05-設計代號/` 和詞彙表）
3. 照 CLAUDE.md「行動前先給計畫」，把下面的切法給多米看，他點頭再動工。每片推上 `swiftui` 都要等 iOS check 綠（`bash ios/tools/watch-check.sh`），看過截圖再做下一片：
   - ✅（2026-11-23 做完，1edf80e、e9b7888、2a22ce3，CI 全綠；多米說另一條 SwiftUI 線停了）片 1 外殼：四個分頁改三個，右上角更多和平常的我，行前拆成檢查這趟、須知、花費三個推進頁（A1 頂端、A7、A15、A17、A18、Check、Notes）。主要動 `Radish/App/RadishApp.swift`、`Screens/Prep*.swift`、`Screens/MeScreen.swift`、`Sheets/MoreSheet.swift`
   - 片 2 這一天的講：每一天最下面的常駐輸入列、說法、小標；送出後升起「剛剛那一則」半頁（A1、A1-Keyboard、A2、A3），加沒網路、句數用完、沒回好（A19–A21）和確認卡。主要動 `Screens/TripScreen*.swift`、`Sheets/ChatSheet.swift`
   - 片 3 問 AI 分頁：對話從彈出卡搬成分頁，最上面「在看：第 N 天」可以換天（A14）
   - 片 4 一站：彈出卡改推進頁，輸入列小標換成站名；移到別的時段的格子、給司機看、過敏告知卡（A5、A6、A11、A13）。主要動 `Sheets/StopSheet*.swift`、`Components/AllergyCardView.swift`
   - 片 5 路線、附近、拔起來（A8、A12、A10）。附近要照距離排，`Plan.swift` 的 `nearbyPool` 現在只回名字
   - 片 6 剛排好那張卡、回來後、去過的那一趟（A4、A9、A16）
   - 開一趟（New-Say／New-Form）等多米答 ❓49
4. 要給多米真機看就推 `tf-4` 標籤出 TestFlight，出版前改 `.github/workflows/ios.yml` 的 TESTFLIGHT_NOTES

## 🗑️ 這次會話的雜訊（下次別重新討論）

- 畫布的規矩（寫一張送一張、發布前先讀、不自己截圖）只跟改線框有關，寫程式用不到
- A1、A3 原本的 5 分鐘、133 → 81 是舊估算，已全部改掉
- 同一天另一條線在 swiftui 上的 commit（5c1d537、cadf4ec、222f522、6ff90dc）跟線框無關，只有確認卡要接進 A3 半頁
