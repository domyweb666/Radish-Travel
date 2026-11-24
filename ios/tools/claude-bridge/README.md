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
- 同一時間只跑一句，後面最多再排兩句，多的直接回 429。一句最多跑 170 秒，超過就把 CLI 砍掉。
- 終端機平常只印幾點收到、多少字、花幾秒、成功或失敗，不印你講的話。CLI 失敗時會多印它說的前 200 字，方便查原因；這段不會傳去手機。

## 擋了什麼

拿到網址的人能做的事，是用你的 Claude 額度問一句、拿回一段文字。下面這些是用來不讓他順便讀到電腦上的東西：

- Claude CLI 看到 `@檔案路徑` 會自己把那個檔附進去，`--tools ""` 管不到這一步。這裡開了 CLI 的環境變數 `CLAUDE_CODE_DISABLE_ATTACHMENTS`，另外把送進去的半形 `@` 全部換成全形 `＠`。兩層各自單獨試過都擋得住。
- 提示詞開頭的 `/`、`!`、`#` 換成全形，也帶 `--disable-slash-commands`，不會被當成指令。
- `--setting-sources ""`：你的 `~/.claude` 設定、hooks、`CLAUDE.md` 都不載。再加 `CLAUDE_CODE_DISABLE_CLAUDE_MDS`、`CLAUDE_CODE_DISABLE_AUTO_MEMORY`、`CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`。
- 不給工具、不載 MCP、不存對話。
- 在這次開機才建的空暫存資料夾裡跑。按 Ctrl+C 結束會刪掉；被強制關掉的話會留一個空資料夾在系統暫存區。
- 環境變數只帶 CLI 跑得起來要的那些。`ANTHROPIC_API_KEY` 這類金鑰不帶，所以 CLI 要用 `claude` 登入過，或設 `CLAUDE_CODE_OAUTH_TOKEN`。
- 密碼先算 sha256 再比。body 上限 1MB、60 秒內要送完。沒料到的例外回 500，程式不會停。回給手機的錯誤訊息是固定的幾句，不帶電腦上的路徑。

2026-11-24 在 Windows、Claude Code 2.1.81 上，把 CLI 送出去的內容攔下來看過：同一句 `@絕對路徑`，改之前裡面有檔案內容和 `~/.claude/CLAUDE.md`；改之後兩樣都沒有，剩今天的日期、上面那段系統提示和你送的那句話。

## 沒擋的、沒驗的

- 區網走的是明碼 http。同一個 Wi-Fi 上有人監聽的話，看得到網址裡的密碼、你的行程和 AI 的回答，也能拿那組密碼用你的額度。只在自己家的 Wi-Fi 開，用完就關，不要在咖啡店或飯店開。
- 那幾個 `CLAUDE_CODE_DISABLE_…` 在 `claude --help` 裡查不到，是從 2.1.81 的程式裡找到的。CLI 換版後可能失效，到時候剩全形 `＠` 和 `--setting-sources` 那層。升級 CLI 之後要重驗。
- 公司或系統管理員派的設定（managed settings）照樣會載，這台沒有，沒試過。
- CLI 還是用你的帳號跑，登入資料照樣讀 `~/.claude`。這裡沒有做系統層的隔離（容器、另一個帳號），CLI 自己有漏洞的話擋不住。
- Mac 和 Linux 沒跑過。Windows 上找不到 `cli.js`、退回經 `cmd.exe` 開的那條路也沒驗。
- 猜錯密碼沒有鎖，密碼是 32 個 16 進位字。

`npm test` 用一支假的 `claude` 檢查上面這些，不花額度。它驗的是這支程式交出去的參數和文字，真的 CLI 認不認要另外試。

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

prompt 把半形 `@` 和開頭的符號換成全形後，從 stdin 餵給 `claude -p --output-format text`，CLI 輸出的文字原樣放進 `text`：

```json
{"text": "{\"reply\":\"好\",\"ops\":[]}"}
```

app 會自己從 `text` 裡找 `{…}` 那段 JSON。

出錯時：

| 狀態碼 | 內容 | 什麼時候 |
|---|---|---|
| 400 | `{"error":"要給 {\"prompt\": \"...\"}"}` | body 不是 JSON 或沒有 prompt |
| 401 | `{"error":"密碼不對"}` | 沒帶 `t` 或 `t` 不對 |
| 404 | `{"error":"只有 /ping 和 /ask"}` | 別的路徑 |
| 405 | `{"error":"只收 POST"}` | 方法不對（`/ping` 只收 GET） |
| 413 | `{"error":"body 超過 1MB"}` | body 太大 |
| 429 | `{"error":"前面還有好幾句在排，等一下再試"}` | 已經有一句在跑、兩句在排 |
| 500 | `{"error":"電腦那頭出錯了，細節看終端機"}` | 沒料到的例外 |
| 502 | `{"error":"claude 結束碼 1，細節看電腦的終端機"}` | CLI 開不起來、結束碼不是 0，或沒回任何文字 |
| 504 | `{"error":"timeout"}` | 超過 170 秒 |

網址格式固定是 `http://<IP>:<PORT>/ask?t=<32 個 16 進位字>`。ping 用同一串網址，把 `/ask` 換成 `/ping`。
