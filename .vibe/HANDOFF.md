# Handoff: 0.5「排到能放心」五項做完第一版，review 的修正還在收，沒全綠、沒併、沒出 TestFlight

> 產出時間：2026-11-25（context-guard 到線自動寫）
> repo 根目錄的 `HANDOFF.md` 是產品開工依據，跟這份會話交接是兩回事。
> 分支 `work/checked-data`（從 swiftui 18526ce 開）。origin 停在 d30c2f8；本機多 0e51ea4（資料）、e28f601（測試與場景），沒 push。
> **工作區有沒提交的改動：兩個子代理寫的修正（見下）。先 `git status` 看，不要 reset、不要 checkout 掉。**

## ✅ 這次完成了什麼

多米 2026-11-25 說「照五項做」（五項的由來：`docs/排到能放心-跟現況對照.md`）：
- 1、2 資料：71 個地點（原 52），「挑一間」換真店；狀態官方 28、二手 40、沒查到 3；四批核對加兩個獨立複查。疊在 seoul.json 上的 `Resources/seoul-checked.json`，原始檔、來源原文、合併腳本在 `docs/核對原始檔/`（還沒提交）
- 3 休館日：generate、換一個、附近、restoreSeed、移站、講了改、AI 提示詞都看
- 4 要先訂：一站一則提醒（開賣前 15 分鐘、最晚決定日、其餘併一則），旅途中也留
- 5 須知跟日期走：K-ETA、電子入境卡
- 一站頁：開放、怎麼訂、來源、這天休館、韓文地址
- d30c2f8 的 CI 全綠（run 45542497610，規則 257、UI 31），那時資料還是空的
- 獨立 review 一輪，14 條加低風險若干

## 🚧 還沒做完

兩個子代理在本會話背景跑，改檔但不 commit：
- 規則與資料（擁有 ios/RadishCore 全部）：同組一趟只取一間、白天吃的一天最多一站且一天最多兩站；PlaceFact 加 parts／partsOn，排行程看開放時段，`partClosedWhy`；以後都不排的舊代號（p4 等）要擋新店；NthDay 加 months（p44 每年 3、6、9、12 月第一個週一）；p6 拿掉 decideDays；p16b、p47b 的 book.url 是文章要拿掉；「開賣時間還不知道」的句子；tip 蓋掉舊 tip（南怡島、水原華城、通仁市場、北村）；N 首爾塔改 caution 只提醒；南大門 closed 拿掉；Chat 計數與樂天世界舊檔；餐廳不說休館；datedFact；提醒時區與內文縮短；資料文字；c1、c2 縮到兩行且去空格；Jungsik 改台灣時間；84 種組合掃描測試
- 畫面（擁有 ios/Radish 全部）：同一件事只講一次、餐廳用詞、接 partClosedWhy／cautionWhy、「訂之前要知道的」收合、datedFact、VoiceOver、book.url 是 nil 沒按鈕、tipOf extra、換一個文案；MoveSheet 第 5 天被切、大字按鈕被切、附近的「想要別的條件，跟 AI 講」被切、大字天數分頁、要先訂沒資料只留一句
- 之後：review 修好的 diff 看一遍 → 提交 → push → CI 全綠 → 看有資料的截圖（test29–34：檢查這趟、K-ETA 兩種、N 首爾塔、須知按天、移到休館日、後苑整頁、大字）→ 文件與交接

## 📌 關鍵決策（Agent 先定的，多米可以改）

- 核對資料獨立一個檔，不動 mobile/ 的 seoul.ts
- 二手就標二手；查不到留空；沒查到不猜
- 汗蒸幕換東大門 SPAREX（男女都能去），只收女生的兩家不放；樂天世界不再標要先訂
- 精緻餐廳改晚餐價，每人 5,100–10,300（粗估），花費預估會變高；同分時便宜的排前面
- 提醒維持沒有聲音（權限只有 .alert），要不要加聲音問多米
- 旅遊中途提醒不停，整趟走完才停
- 不畫體力條、開一趟不加欄位、維持首爾、旅伴各自填放第二版

## ⚠️ 要告訴多米

- 愛寶樂園、清溪川、樂天世界、Seoul Sky 官網機器讀不到
- Google 地圖在韓國 11-13 獲准，步行導航報導說最快 2027 年初；根目錄 `HANDOFF.md` 7-2 要更新（沒改）
- 樂天世界海盜船 11-23 起停；中央博物館多個展室修到 2027-01-28；宮殿票價 2027 可能調
- 定稿寫不做記帳，但 app 有自己記的花費
- H：真的打一次 Anthropic API、真機全部沒驗（舊的待辦）；❓29、閘門 1、2

## 📂 下個會話最重要的檔案

- `ios/README.md`、`ios/RadishCore/Sources/RadishCore/{SeoulFacts,Book,Remind,Plan,PlanGenerate}.swift`
- `ios/Radish/Components/StopFacts.swift`、`ios/Radish/Screens/PrepBefore.swift`
- `docs/排到能放心-跟現況對照.md`、`docs/核對原始檔/BRIEF.md`

## ⏭️ 下一步從哪繼續

1. `git status`、`git diff --stat`：看兩個子代理的修正在不在、有沒有做完（對照上面「還沒做完」逐項 grep：placeGroup、partsOn、cautionWhy、datedFact、「訂之前要知道的」）
2. 不完整的派新子代理補；完整的指定檔名提交，`docs/核對原始檔/` 一起提交
3. push work/checked-data，`bash ios/tools/watch-check.sh`（背景跑，約 30 分鐘），派子代理修到全綠並看截圖
4. 全綠後：併回 swiftui（ff），更新 ios/README、`.uiux/05-設計代號/詞彙表`；0.5.0 的 TESTFLIGHT_NOTES 和版號先寫好，tf-7 標籤要多米點頭才推

## 🧩 剩下的工作

- [ ] A：確認 review 修正（規則與資料）完整｜上面清單逐項在、CI 規則測試綠｜ios/RadishCore｜無
- [ ] B：確認 review 修正（畫面）完整｜上面清單逐項在｜ios/Radish｜依賴 A 的簽名
- [ ] C：push、CI 全綠、看有資料的截圖、修畫面｜兩關全綠、截圖逐張看過｜依賴 A、B
- [ ] D：併 swiftui、README、詞彙表、0.5.0 版號與測試說明草稿｜不推標籤｜依賴 C
- [ ] E：報告給多米（含上面「要告訴多米」），問要不要出 tf-7｜依賴 D

## 🗑️ 雜訊

- CI macOS 排不到機器 15 分鐘後 cancelled、0 個步驟，`gh run rerun <id> --failed`；推新 commit 會取消舊那輪
- Bash 單一指令超過 8KB 會壞，大檔用 Write；提交要指定檔名，不准 commit -a
