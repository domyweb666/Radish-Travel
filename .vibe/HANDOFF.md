# Handoff: A 版線框做成 SwiftUI、接 AI、出了 TestFlight 0.3.0（4）；下一步做開一趟 B 版和補驗

> 產出時間：2026-11-24 23:05
> 前一會話的最後狀態，給下一個會話接續用
> 注意：repo 根目錄的 `HANDOFF.md` 是產品的開工依據，跟這份會話交接是兩回事。
> 分支 `swiftui`（未併 main），程式停在 a4591a0，後面只有交接的 commit，跟遠端同步。

## ✅ 這次完成了什麼

- 片 1–6 照 A 版線框做完：三個分頁（這趟／問 AI／旅行）、推進頁、講的那一列、問 AI、一站、路線、附近、拔起來、剛排好、回來後、去過的那一趟
- 平常的我可以填 Claude API 金鑰，直接打 Anthropic Messages API（`claude-opus-5-5`、effort low，金鑰存鑰匙圈）
- 平常的我可以連電腦的 Claude CLI：電腦跑 `ios/tools/claude-bridge`（npm start），手機掃 QR code；優先順序是電腦 CLI、金鑰、後端
- 路線半頁「請 AI 提一個改法」換成「這次會改」那一面（`RouteSuggest.swift`，沒接 AI 時手機算）
- 句數規則先定：只有走後端才算，第一趟 20 句、之後 100 句
- TestFlight 0.3.0（4）已上傳（tf-4，工作流全綠），測試說明已填
- 2026-11-24 多米選 ❓49 的 B（表單多一格「想怎麼玩」）

## 🚧 還沒做完 / 待決定

- 開一趟 B 版還沒做。現在的開一趟完全不經過 AI，用的是 `generate()`
- 等多米真機回饋（0.3.0（4））：掃 QR、填金鑰、震動、鍵盤、關 Wi-Fi
- ❓49 的對照圖有錯，多米是看著它選 B 的，要請他確認一次。圖上說 A 要等 AI 聽懂、要等兩次 AI、沒接 AI 或沒網路第一步就卡住，都不對：`02-流程` 2-1 和 5-5 寫「我聽到的」是手機比對。兩種都只在排的時候等 AI。A 剩下的缺點是步驟比較多（講一句、補還缺的、第一次看說明、等 AI）
- 產品決定還沒答：❓19（沒網路、AI 沒排出來時給不給內建排法）、❓29（剩幾句在哪顯示、要不要賣）、❓48（拔起來的蘿蔔人）
- 回報這則沒做（沒有後端）；閘門 1、2 都沒過；真機沒驗過任何一項

## ⚠️ 已知問題（上一個會話講錯或沒驗的，先處理）

1. 跟多米說「按復原不會退句數」，程式不是這樣：`AppStore.undo()` 會把 `trip` 換回舊的，句數跟著退；整趟重排（`ownOf` 只帶走花費、匯率、航班）會歸零。現在沒有後端，句數不會真的擋人，但規則和程式對不上
2. 同意（`aiConsent`）只有一個旗標。先同意送到某一處，之後改填金鑰或改連電腦，不會再問一次，送去的地方卻換了。跟「不騙人」有關
3. 跟多米說截圖「逐張對過線框」，實際只看了一部分：第一輪 32 張看 6 張左右，第二輪 38 張看 7 張左右。沒看過的：移到別的時段、拔蘿蔔、旅行、附近以外的大多數捲動圖。完全沒有截圖的畫面：給司機看、過敏告知卡、剛排好那張卡（測試行程今天出發，不會出現）、回來後那張卡、去過的那一趟、沒網路、沒回好、第一次同意、路線「這次會改」、金鑰頁、連電腦頁
4. 最後一版的路線截圖看得出問題：半頁打開時地圖佔掉大半，往下捲會變成拖地圖，地圖跑到梨泰院、站點不見，每一段和「請 AI 提一個改法」在下面看不到
5. 六個 subagent 寫的 Swift 和轉接程式沒有人做過 code review，只靠編譯、規則測試和三條 UI 測試
6. 直接打 Anthropic 的那條路沒有用真的金鑰試過。填金鑰時的試打不帶 `fallbacks`，正式的請求帶 `fallbacks: "default"` 加 beta 標頭；試打會過、正式的請求可能回 400
7. 電腦轉接：`/ping`、`/ask` 是 subagent 實跑過（一句 5.3 秒），主會話沒重跑；手機掃描、Ctrl+C 關閉、CLI 真的不能讀檔（靠 `--tools ""`）都沒驗。區網是明碼 http。多米的訂閱能不能這樣用，沒有查 Anthropic 的條款，只說給自己開發測試

## 📌 關鍵決策（這次定下來的，下次別再爭論）

- 介面照 A 版線框，三個分頁；開一趟選 B（表單多一格），做之前先請多米看一次更正過的說明
- 接 AI 的優先順序：電腦 CLI、自己填的金鑰、後端
- 句數規則照 `Chat.swift` 的 `aiLeft` 註解，多米說「你幫我設定好」，Agent 先定的，之後可改
- 直接打 API 用 `claude-opus-5-5`、effort low；擋下時自動換模型已開，多米說不要就拿掉
- 版號升 0.3.0；下一版推 `tf-5`，出版前改 `.github/workflows/ios.yml` 的 TESTFLIGHT_NOTES
- 多開 subagent、各管各的檔、不 commit；同一個資料夾，不用 worktree

## 📂 下個會話最重要的檔案

- `ios/README.md`（規矩、CI 怎麼看）、`ios/UI-PORTING.md`（畫面之間的簽名）
- `ios/Radish/App/AppStore.swift`（talk、aiOn、talkLeft、undo）、`ios/Radish/App/Nav.swift`、`Sheets.swift`
- `ios/RadishCore/Sources/RadishCore/Chat.swift`（askAI、askClaude、aiLeft）、`RouteSuggest.swift`
- `ios/Radish/Screens/StartTrip.swift`、`ios/Radish/Components/TripForm.swift`（開一趟 B 版要改的）
- `.uiux/03-線框/線框/New-Form.dc.html`、`New-Consent.dc.html`；`.uiux/02-流程-暫定.md` 2-1、5-6 的 S02、S03
- `ios/Radish/Sheets/MapSheet.swift`（路線半頁的地圖問題）
- `ios/tools/claude-bridge/`（bridge.mjs、README.md）

## ⏭️ 下一步從哪繼續

1. 先問多米兩件事：看過更正後的說明，開一趟還是 B 嗎；TestFlight 0.3.0（4）在手機上哪裡怪
2. 不用等回覆就能做的先做：工作包 A、C、D（A、C 不共用檔案，D 唯讀，可以平行）
3. 每推一次都跑 `bash ios/tools/watch-check.sh <輸出資料夾>` 等綠，截圖要全部打開過才能說看過
4. 全部做完再一次交給多米，出版推 `tf-5`

## 🧩 剩下的工作（工作包，接續時派給子代理）

- [ ] A：句數不被復原和重排退掉｜復原、整趟重排、照新設定重排後 `aiUsed` 不變，有測試｜`AppStore.swift`、`TripScreen.swift`（replan）、`RadishCore/Tests`｜無
- [ ] B：同意要記送去哪裡｜換成金鑰或連電腦後，第一次送之前再問一次，說明寫對地方；舊存檔讀得出來｜`AppStore.swift`、`Models.swift`、`ReplySheet.swift`、`MeEditors.swift`、`MapSheet.swift`｜依賴 A、C（共用 AppStore、MapSheet）
- [ ] C：路線半頁的地圖不擋捲動｜打開就看得到總分鐘和「請 AI 提一個改法」，捲動不會拖地圖｜`MapSheet.swift`、`DayMap.swift`｜無
- [ ] D：唯讀 code review 片 2–6 和接 AI 的程式｜列出正確性問題，附檔案行號和會壞的情況，不改檔｜只讀｜無
- [ ] E：開一趟 B 版｜表單多一格「想怎麼玩（可以不填）」。沒填照現在；有填就先用 `generate()` 排，再把那句當第一句問 AI 照著改，第一次先看同意說明；沒網路或沒接 AI 時行程照樣排出來，並老實說那句沒有送｜`StartTrip.swift`、`TripForm.swift`、`Models.swift`（TripDraft）、`AppStore.swift`、`TripCards.swift`｜依賴 A、B，也要等多米確認 B；有填那句的做法是 Agent 的建議，先講給多米聽
- [ ] F：補截圖和測試｜上面第 3 點列的每個畫面至少一張截圖，全部看過，跟線框不一樣的列出來｜`RadishUITests/`、必要時加測試用啟動參數｜依賴 A、B、C、E
- [ ] G：D 找到的問題修完｜逐條修或寫明不修的原因｜看 D 的清單｜依賴 D
- [ ] H：真的打一次 Anthropic API｜多米用自己的金鑰在 app 裡填一次、講一句；回 400 就拿掉 fallbacks｜`Chat.swift`｜要多米，金鑰不經過對話

## 🗑️ 這次會話的雜訊（下次別重新討論）

- 測試點到懸浮分頁列、講的那一列小標太寬、測試字串斷行，都修好了
- 片 1–6 的拆法和誰改哪個檔，已經做完
- 問過能不能連 Claude CLI：能，已做
