# Handoff: 開一趟 B 版、兩輪 review、順路清單分趟都做完；TestFlight 0.4.1（6）已出，等多米真機回饋

> 產出時間：2026-11-25
> 前一會話的最後狀態，給下一個會話接續用
> 注意：repo 根目錄的 `HANDOFF.md` 是產品的開工依據，跟這份會話交接是兩回事。
> 分支 `swiftui`（未併 main），程式停在 f9efb0f，後面只有交接的 commit。

## ✅ 這次完成了什麼

- A 句數、B 同意記送去哪裡、C 路線半頁、D 兩份 code review、E 開一趟 B 版、F 補截圖、G review 的問題，全部做完
- 另外對這一輪的新程式再 review 一次，十條都修了
- 電腦轉接補安全洞：`@路徑` 會讀到電腦上的檔、CLAUDE.md 被帶進去、壞權杖讓程式掛掉（實測修前修後，bridge.test.mjs 6 條）
- CI 在 f334638 全綠：規則測試 169 條、UI 測試 26 條（新增 SceneUITests 23 條，`-uitest-scene`、`-uitest-ai`、`-uitest-dest`、`-uitest-offline`、`-uitest-dark`，只在 Debug）
- TestFlight 0.4.0（5）、0.4.1（6）都上傳了，測試說明已填
- 順路清單改成 `Trip.pool`，每趟分開、可以拿掉能復原；下一站卡的蘿蔔、拔蘿蔔底下的蘿蔔人拿掉（b67df68，CI 規則 184、UI 27 全綠）

## 🚧 還沒做完 / 待決定

- H：真的打一次 Anthropic API（要多米的金鑰，不經過對話）。格式由 review 對過文件，沒有實際打
- 真機沒驗過任何一項：震動、掃 QR、首次相機權限、提醒、注音打到一半收鍵盤、VoiceOver
- 產品決定：❓29 沒答（❓19、❓48 多米 2026-11-25 定了）；閘門 1、2 沒過；併 main 沒談

## ⚠️ 已知問題

1. 一站頁寫「最想講的一件事」時，講的那一列浮在鍵盤上，把輸入框下緣切掉一點（字看得到）。可以改成那時把講的那一列收起來
2. 跟線框不一樣、沒修：旅途中天數列在下一站卡下面（A2 在上面）；「更多」是全高（A7 半頁），「復原上一步」沒寫復原什麼；返回只有箭頭（A5 有「第 2 天」）；按完套用對話還寫「下面那張卡按套用」；移時段格子右邊沒對齊；沒有「剛改過」標記、「回報這則」
3. 拔蘿蔔那一下還寫「收進籃子。」，「蘿蔔籃」11-16 已改名「旅行」，要不要改字問多米；`RadishBuddy`／`BuddyPoses` 沒人用了，檔案和測試還留著
4. 沒接 AI 的句子多件事又沒標點、沒「想」字，可能仍由手機答
5. 全部清掉不刪照片檔（怕貼回備份看不到），說明有寫
6. 一站打字中切趟按復原，那句只在提示條留 8 秒
7. 轉接程式：CLI 的關閉附檔環境變數不在 --help 裡，CLI 升級要重驗；區網明碼 http；只在 Windows 驗過；多米的訂閱能不能這樣用沒查條款
8. 截圖：Scene 63fcad5 那輪全部看過，f334638 只看改過的 15 張（鍵盤、開一趟、同意、深色、大字、路線）；Flow 的 38 張由子代理看，主會話只看過路線和移時段

## 📌 關鍵決策（Agent 先定的，多米可以改）

- 想怎麼玩：行程先由手機排好才問 AI；沒送成那句留在第 1 天那一列，重開 app 會放回，使用者刪掉或改過就不再放回
- 有去過的站就整趟不重排（橫幅、問 AI、說「重排」都擋）
- 收起來：一站都沒去過就放到「其他排好的」；去過的存整趟，看得到花費、機票、沒去的站
- 復原「開新的一趟」時新排的那趟留在架上；換趟一律留一步可復原
- 同意照「種類＋主機＋埠」記；舊的同意當沒同意；貼上備份不帶同意；換金鑰不重問
- 「不要這一版」時順路清單留給下一趟；去過的那一趟也列清單，只能看
- 問了 AI 幾句依 Trip.id 記在 aiLog，只多不少；「不要這一版」再開算新的
- 轉接排隊上限兩句，ANTHROPIC_API_KEY 不帶給 CLI（只吃訂閱登入）
- 手機、電腦轉接都要新版才對得上；電腦端要重新 npm start

## 📂 下個會話最重要的檔案

- `ios/README.md`、`ios/UI-PORTING.md`
- `ios/Radish/App/AppStore.swift`（復原、換趟、talk、talkWish）、`ios/Radish/App/UITestScenes.swift`
- `ios/RadishCore/Sources/RadishCore/{Chat,TripActions,Spend,Models}.swift`
- `ios/RadishUITests/SceneUITests.swift`、`.github/workflows/ios.yml`

## ⏭️ 下一步從哪繼續

1. 下一版：改 TESTFLIGHT_NOTES 和版號，CI 綠了推 `tf-7`（要多米點頭）
2. 多米有真機回饋：先收進工作包，再派子代理
3. 沒回饋：從已知問題 1、2 挑著修

## 🧩 剩下的工作

- [x] 出 TestFlight 0.4.0（5）、0.4.1（6）
- [ ] H：真的打一次 Anthropic API（要多米）；回 400 就拿掉 fallbacks｜`Chat.swift`
- [ ] 已知問題 1、2 的畫面修正｜`StopScreen*`、`TalkBar`、`TripScreenParts`、`MoreSheet`、`MoveSheet`｜無
- [x] pool 分趟、能刪

## 🗑️ 雜訊

- CI macOS 排不到機器會 15 分鐘後顯示 cancelled、0 個步驟，`gh run rerun <id> --failed` 就好；推新 commit 會取消舊的那輪
