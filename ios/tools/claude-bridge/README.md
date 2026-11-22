# claude-bridge：讓 iPhone 用這台電腦的 Claude CLI 回答

開發測試用。iPhone 上的蘿蔔旅行在「跟 AI 講」送出一句話，會送到這台電腦，這支程式把它交給你登入的 Claude CLI（`claude -p`），再把回答傳回手機。還沒有後端、也不想在手機裡填 API 金鑰的時候用。

## 怎麼開

先確認這台電腦裝好 Claude Code，而且 `claude` 已經登入（終端機打 `claude --version` 有版本號就行）。

```
cd ios/tools/claude-bridge
npm install
npm start
```

開起來會印一個 QR code，下面是同一串網址的文字版，長這樣：

```
http://192.168.0.173:8787/ask?t=0123456789abcdef0123456789abcdef
```

`t=` 後面是這次開機隨機產生的密碼，每次 `npm start` 都會換，所以重開之後手機要重掃一次。電腦有好幾張網卡時會每個 IP 都印一行網址，QR code 只畫第一個；第一個連不上就改貼別行。

要換埠號或指定模型：

```
PORT=8788 npm start
CLAUDE_MODEL=sonnet npm start
```

（PowerShell 寫成 `$env:PORT=8788; npm start`。）

按 Ctrl+C 結束。

## 在 app 裡怎麼接

平常的我 → 連電腦的 Claude CLI → 掃 QR code。

模擬器沒有相機，把終端機印的那串網址整串複製貼上。

## 限制

- 電腦要開著，而且這支程式要一直跑著。關掉之後手機就問不到了。
- iPhone 跟這台電腦要連同一個 Wi-Fi。第一次連的時候 iPhone 會問要不要讓蘿蔔旅行找區網裝置，要按允許。按成不允許的話，到 iPhone 的設定 → 隱私權與安全性 → 區域網路，把蘿蔔旅行打開。
- Windows 防火牆第一次會跳出來問要不要讓 Node.js 接受區網連線，要按允許（至少勾私人網路）。按錯了到「Windows 安全性 → 防火牆與網路保護 → 允許應用程式通過防火牆」把 Node.js 打勾。
- 用的是你自己的 Claude 訂閱額度。只給自己開發測試用，網址和密碼不要給別人。
- 同一時間只跑一句，後面送來的排隊。一句最多等 170 秒，超過就砍掉。
- Claude CLI 是在一個空的暫存資料夾裡跑，關掉所有工具、不載 MCP、不存對話，所以它只能回文字，碰不到這台電腦的檔案。
- 終端機只印幾點收到、多少字、花幾秒、成功或失敗，不印你講的話和 AI 的回答。

## 協定

所有請求都要在網址帶 `?t=<密碼>`，密碼不對回 401 `{"error":"密碼不對"}`。

### `GET /ping?t=<密碼>`

看電腦這頭還在不在。

```json
{"ok": true, "name": "<電腦名稱>", "cli": "2.1.81 (Claude Code)"}
```

`cli` 是 `claude --version` 的輸出，取不到就是空字串。

### `POST /ask?t=<密碼>`

body 是 JSON，最大 1MB：

```json
{"prompt": "app 組好的整段提示詞"}
```

prompt 從 stdin 餵給 `claude -p --output-format text`，CLI 輸出的文字原樣放進 `text`：

```json
{"text": "{\"reply\":\"好\",\"ops\":[]}"}
```

app 會自己從 `text` 裡找 `{…}` 那段 JSON。

出錯時：

| 狀態碼 | 內容 | 什麼時候 |
|---|---|---|
| 400 | `{"error":"要給 {\"prompt\": \"...\"}"}` | body 不是 JSON 或沒有 prompt |
| 401 | `{"error":"密碼不對"}` | 沒帶 `t` 或 `t` 不對 |
| 413 | `{"error":"body 超過 1MB"}` | body 太大 |
| 502 | `{"error":"<CLI 錯誤訊息前 200 字>"}` | CLI 結束碼不是 0，或沒回任何文字 |
| 504 | `{"error":"timeout"}` | 超過 170 秒 |

網址格式固定是 `http://<IP>:<PORT>/ask?t=<32 個 16 進位字>`。ping 用同一串網址，把 `/ask` 換成 `/ping`。
