# 核對首爾地點：共同規則

今天 2026-11-25。目的：app「蘿蔔旅行」的賣點是放心，寫錯休館日比沒寫更糟。

## 先讀
- `E:\蘿蔔旅行\ios\RadishCore\Sources\RadishCore\SeoulFacts.swift`：每一欄的型別和意思，照它的欄位名輸出
- `E:\蘿蔔旅行\ios\RadishCore\Sources\RadishCore\Resources\seoul.json` 的 places：你負責的那幾個現在的內容
- 這兩個檔只讀。整個 repo 一個檔都不准改

## 怎麼查
- 先找官方頁（景點官網、文化財／國家遺產廳、市政府、品牌官方、官方訂票頁），韓文頁優先於英文頁。真的打開讀內容，搜尋摘要不算讀過
- 打不開官方頁（擋機器、要 JS）可以試：換英文版、手機版、官方公告頁、VisitKorea／Visit Seoul（這兩個寫 second）
- 打開網頁的方法：WebFetch（要先用 ToolSearch 載入）、web-fetch 子代理、curl。不要用瀏覽器面板（大家共用會打架）。對外請求不要帶任何個人資訊
- status：這個地點的休館日或開放時間是你親自讀官方頁得到的寫 official；只有媒體、部落格、觀光網站寫 second；查不到寫 none（這時其他欄位大多是 nil）
- 每一個欄位只寫來源有講的。來源沒講就不要寫那一欄。不准用常識、記憶補。來源互相打架就寫不確定的那欄不填，並在 notes 說明
- closed 寫 [] 代表「來源明講全年無休或沒有固定休」。沒講就不要寫 closed
- shift 只有來源明講「碰到國定假日照開／改休隔天」才寫
- closedOn：固定日期寫 "01-01"；農曆節日當天寫 "seollal"、"chuseok"；連假三天都休寫 "seollal3"、"chuseok3"
- book：只有需要或建議先訂的才寫。opensDays＝參觀日往前幾天開賣（參觀日那天不算）；opensAt 用韓國時間 24 小時制 "HH:MM"。只有來源明講才寫
- decideDays＝最晚幾天前還能免費取消，來源明講才寫
- foreigner：外國人訂不訂得到（有沒有外文頁、要不要韓國手機門號、收不收海外卡），來源有講才寫
- 價格寫韓元，例如 "大人 3,000 韓元"
- 文字用台灣繁體中文、平實、一句話。不寫「最佳」「必去」「保證」「完美」。不用破折號。時間寫 24 小時制
- tip：一句給走在路上的人看的須知，只寫核對過的事，不重複 hours／closed 那些欄位已有的內容；沒有就不寫
- 歇業、搬家、整修、長期不開：一定要查。寫進 gone（永久或不知道什麼時候開）或 off（有期間）

## 沒指名的（kr 是空字串的那幾個）要換成真店
- 每個換成 2 到 3 家查得到、現在還在營業的真店，放進 add：`{"after":"p4","place":{...}}`，並把原本的 id 放進 drop
- 新 id 是原 id 加 a、b、c（p4a、p4b）。place 的欄位照 Models.swift 的 Place：id、n（中文名）、kr（韓文名，要能拿去 Naver 地圖搜）、a、s、c、lat、lng、b、fee、tip、l、up、f、ic。a 要是它真正所在的帶（見 seoul.json 的 area；跟原本不同就寫在 notes），s、c、f、ic、l 沿用原本的
- lat、lng 要真的查（官方頁、OpenStreetMap Nominatim 用韓文地址查，User-Agent 用 generic-client），不准編。查不到座標的店就不要選
- fee 是每人粗估新台幣，沒根據就沿用原本那個值
- 挑店標準：官方或可靠來源查得到地址和營業資訊、開了一陣子、外國人去得到。不看業配、不寫評分。不要挑只有部落格一篇提到的
- 每一家新店都要在 facts 有一筆
- 真的找不到就不 drop，在 notes 說明

## 輸出
把結果寫成一個 JSON 檔（UTF-8，不要 BOM），路徑在你的任務裡：
```
{"facts": {"p0": {...}}, "drop": [], "add": [], "evidence": [{"id":"p0","field":"closed","url":"...","said":"來源原文那一小句，15 個字以內","official":true}], "notes": ["..."]}
```
- src 裡的 name 寫網站名，url 是你真的打開過的那一頁
- 每一個 closed／closedOn／shift／off／gone／opensDays／opensAt／decideDays／last 都要有一筆 evidence
- 寫完用 `PYTHONIOENCODING=utf-8 python -c "import json;json.load(open(r'路徑',encoding='utf-8'))"` 驗一次（這台用 python，不是 python3；Bash 單一指令不要超過 8KB，寫檔用 Write）
- 回報給我：幾個 official／second／none、最要注意的發現（歇業、整修、資料包原本寫錯的）、哪些查不到。不要貼整份 JSON
