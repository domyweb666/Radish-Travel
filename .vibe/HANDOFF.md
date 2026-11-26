# Handoff: TestFlight 0.7.0（9）已出（代購、星級、去過的往後排），等多米真機回饋

> 產出時間：2026-11-27（0.7.0 出版後更新；0.6.0 那晚的內容照舊留在下面）
> repo 根目錄的 `HANDOFF.md` 是產品開工依據，跟這份會話交接是兩回事。
> 這晚的細節看根目錄 `OVERNIGHT.md`。

## 分支現況

- `swiftui`：2026-11-27 快轉到 b96488a（work/tourist-first 加 0.7.0 版號），tf-9 打在 b96488a，run 45899186863 成功，建置號 9，測試說明已填。下一版是 tf-10。0.6.0 是 tf-8（58db54d）。
- `overnight-20261126-1105`、`work/qc-0013`：都已經包含在 swiftui 裡，可以不用了（沒刪）。
- 沒追蹤的 `docs/聯盟連結-排序規則-草案.md` 是 QC-0013 問題單會話寫的 #99 提案，等多米看，不要 add 也不要刪。
- `work/affiliate`（b394a0a，從 swiftui c03044c 開，QC-0013 問題單會話）：#99 Klook／KKday 聯盟連結的連結表與畫面，網址都還空著，畫面跟原本一樣。多米 2026-11-26 定的規則寫在 `docs/聯盟連結-排序規則-草案.md`（已經 commit 進這條分支）：官網 → Klook → KKday 固定順序、只放要先訂又不是吃的六站、分潤寫在平常的我的「排序和連結」（表裡有網址才出現）。`BuyLinksTests` 掃 RadishCore，除了 BuyLinks.swift 都不准讀連結表。CI 45825406475：swift test 綠、BuyLinksUITests 三條兩輪都過；沒全綠是 SceneUITests test42（兩輪分別高 5 點、低 52 點）和 FlowUITests test03（重跑才掉），都是這趟頁換天落點不穩，swiftui 58db54d 跑同一份程式剛好過。work/tourist-first 在試修（land() 校正 4 次）。沒併 swiftui。下一步：多米申請兩家聯盟帳號、確認條款（價格是否一樣、揭露要不要放在連結旁），拿到網址填 buy-links.json，並把 BuyLinksTests「表目前全空」那條改掉。
- `work/tourist-first`（b96488a，已經整條在 swiftui 裡，2026-11-26 晚上另一個會話做的）：多米要的三件，已出 0.7.0。這條分支是用暫存 index 加 commit-tree 寫進去的，沒有 checkout 過，HEAD 留給 work/affiliate。
  1. 代購清單：這趟頁「代購」入口，推進頁 ErrandsScreen，每列記誰託的、買什麼、幾個、買到了沒。加、改、勾、刪都能復原。重排、放一邊、收起來都會留著；「不要這一版」時先存在 AppState.errands，放進下一趟。畫布第 51 版三版總覽都補了代購。
  2. 星級：每個地點估 1 到 3 星，依據寫在 `docs/星級依據.md`。第一次來，三星 +1.5、二星 +0.5；去過首爾以後縮成三分之一。使用者自己的喜好永遠比星級重要。附近清單會顯示「估 ★★☆」；AddSheet 沒有候選清單，所以沒做。seoul.json 的 star 只加在 ios 這份，重新跑 export-seoul.ts 會被洗掉。
  3. 去過的往後排：用 visitedOf(baskets) 算，開一趟、三種重排都有傳進去，去過的要真的沒別的可排才會排，而且會講出來。問 AI 時候選會帶星級和「去過 N 次」。
  - CI：第 5 輪 run 45848639817 全綠（Linux 366 條、macOS 51 條 UI 測試）。land() 的校正試過改成 4 次，那一輪 test24 和 StopQC test02 在點的時候畫面還在捲，結果掉了，所以改回 2 次；最後只留 test42 點第 4 天之後多等一秒（pause 3）。test42 在 work/affiliate 也會兩個方向不穩，它併回去之前還會掉。2026-11-27 多米說併進去出版，已併 swiftui、出 0.7.0（9）。
  - 等多米：真機看代購頁和星級排出來的行程；要不要在 AddSheet 加熱門清單；export-seoul.ts 要不要也帶星級。

## ✅ 這晚做完

1. CI 修綠：點天數、旅途中打開捲到今天，那一天會停在地圖和分頁下面（TripScreen.swift 的 landing／land／settle，Scaffold.swift 回報看得到的高度；捲完量一次落點，差太多自己再捲）。一站頁測試避開黏頂那塊（StopQCUITests 的 pinBand）。
2. 旅途中移站：已經過了的時段灰掉不能選，規則層 moveItem 也擋，說法跟用講的同一句（Now.swift 的 slotPastWhy）。
3. 文字：吃的講「開放訂位」「訂位頁」；來源名不帶日期（日期搬到 date 欄位）；ios/ci/README.md 版號。
4. 補五間路邊和市場（全是二手資料），只吃路邊的人空晚上 63.5% → 32.4%，五天以內 0。掃描腳本 `ios/tools/scan-street-dinner.mjs`。
5. 根目錄 HANDOFF.md 7-2 補了 11-13 Google 地圖在韓國的消息。

## ❓ 等多米決定

- 下一版標籤是 tf-10，不要打在 `[skip ci]` 的 commit 上
- QC-0013 #101 去過的地圖、#102 旅行分頁、#103 總覽：設計稿各三版，要先測、選版（閘門 2）
- #97 邀請一起排（要後端）、#99 聯盟連結（跟「排序沒有私心」怎麼放）
- 定稿寫不做記帳，但 #106 已經能在一站記花費
- ❓49 表單多一格，#104 改月曆後還要不要
- 只吃路邊：要不要改成白天不排路邊的店（試算空晚上會再降到 11%），或再補十幾間

## ⚠️ 還沒驗

- 真機全部沒驗；真的打一次 Anthropic API 沒驗；❓29、閘門 1、2
- 五間新店的營業時間都是二手資料（明洞路邊攤只有一篇部落格）
- 官網讀不到：愛寶樂園、清溪川、樂天世界、Seoul Sky；兩支米其林電話沒打過；海盜船停駛、中央博物館展室整修、宮殿 2027 票價這幾件有時效
- 從已經過了的時段「移出來」沒擋（昨天沒去成的站還能挪到之後），要不要擋待定

## 🗑️ 雜訊

- 這個資料夾同時有別的會話在跑（11-26 QC-0013 問題單以為還在 work/qc-0013，commit 落到 overnight 分支）。切分支前先看有沒有別的會話在用這個資料夾。
- CI macOS 排不到機器 15 分鐘後 cancelled，`gh run rerun <id> --failed`；同一條分支推新 commit 會取消舊那輪。
- 這台沒有 Swift；排行程規則可以移植成 node 掃描比對（例：scan-street-dinner.mjs）。
- 提交要指定檔名，不准 commit -a。
