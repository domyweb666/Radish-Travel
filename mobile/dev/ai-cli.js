// 測試階段用：還沒有後端和 Anthropic 金鑰時，讓開發伺服器自己接「用講的改行程」。
// app 把提示詞 POST 到 /__ai，這裡在這台電腦上跑 `claude -p`（用這台登入的 Claude Code 帳號），回 {text}。
// 只在 .env.local 設了 EXPO_PUBLIC_AI_ENDPOINT=/__ai 時才會掛上（看 metro.config.js）。正式版不走這條。
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROUTE = '/__ai';
const BODY_MAX = 200 * 1024;
const TIMEOUT_MS = 120 * 1000;
const MODEL = process.env.RADISH_AI_MODEL || 'sonnet';

// 在空資料夾裡跑，不給任何工具、不載 MCP：它只能回文字，碰不到這台電腦的檔案
const CWD = path.join(os.tmpdir(), 'radish-ai-cli');
// 換掉 Claude Code 自己的系統提示，不然它會把 app 送來的提示詞當成可疑的貼上內容。只用英數，免得過 shell 時引號出事
const SYSTEM = 'You are the backend of a travel planning app. The user message is the full request built by the app itself. Follow it and output exactly the JSON object it asks for, with no other text.';
const CMD = `claude -p --output-format json --tools "" --strict-mcp-config --no-session-persistence --model ${MODEL} --system-prompt "${SYSTEM}"`;

function send(res, code, obj) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(obj));
}

function ask(prompt) {
  return new Promise((resolve, reject) => {
    fs.mkdirSync(CWD, { recursive: true });
    const child = spawn(CMD, { cwd: CWD, shell: true, windowsHide: true });
    let out = '';
    let err = '';
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error('claude cli 太久沒回'));
    }, TIMEOUT_MS);
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (err += d));
    child.on('error', (e) => (clearTimeout(timer), reject(e)));
    child.on('close', (code) => {
      clearTimeout(timer);
      try {
        const data = JSON.parse(out);
        if (data.is_error || typeof data.result !== 'string') throw new Error(String(data.result || 'claude cli 回的不是文字'));
        resolve(data.result);
      } catch (e) {
        reject(new Error(`claude cli 結束碼 ${code}：${(err || e.message).slice(0, 300)}`));
      }
    });
    child.stdin.end(prompt);
  });
}

/** Metro 的 middleware。不是 /__ai 的請求原封不動往下傳 */
function aiCli(req, res, next) {
  if (!req.url || req.url.split('?')[0] !== ROUTE) return next();
  if (req.method !== 'POST') return send(res, 405, { error: '只收 POST' });
  let body = '';
  let tooBig = false;
  req.on('data', (d) => {
    body += d;
    if (body.length > BODY_MAX) tooBig = true;
  });
  req.on('end', async () => {
    if (tooBig) return send(res, 413, { error: '內容太長' });
    let prompt = '';
    try {
      prompt = String(JSON.parse(body).prompt || '');
    } catch {
      /* 下面一起擋 */
    }
    if (!prompt) return send(res, 400, { error: '要給 {"prompt": "..."}' });
    const t0 = Date.now();
    try {
      const text = await ask(prompt);
      console.log(`[ai-cli] 回了，${((Date.now() - t0) / 1000).toFixed(1)} 秒，模型 ${MODEL}`);
      send(res, 200, { text });
    } catch (e) {
      console.error(`[ai-cli] 失敗：${e.message}`);
      send(res, 502, { error: e.message });
    }
  });
}

module.exports = { aiCli, ROUTE };
