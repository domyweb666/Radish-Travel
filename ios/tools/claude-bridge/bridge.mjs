// 開發測試用：讓 iPhone 上的蘿蔔旅行，透過這台電腦登入的 Claude CLI 回答「跟 AI 講」。
// app 把 {"prompt": "..."} POST 到 /ask，這裡把 prompt 從 stdin 餵給 `claude -p`，原樣回 {"text": "..."}。
// 做法改寫自 mobile/dev/ai-cli.js（Expo 版的 /__ai）。正式版不走這條。
import { spawn, execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import qrcode from 'qrcode-terminal';

const PORT = Number(process.env.PORT) || 8787;
const MODEL = (process.env.CLAUDE_MODEL || '').trim();
const BODY_MAX = 1024 * 1024;
const TIMEOUT_MS = 170 * 1000;
const TOKEN = crypto.randomBytes(16).toString('hex');
const IS_WIN = process.platform === 'win32';

// 在空資料夾裡跑，不給任何工具、不載 MCP、不存對話：它只能回文字，碰不到這台電腦的檔案
const CWD = path.join(os.tmpdir(), 'radish-claude-bridge');
// 換掉 Claude Code 自己的系統提示，不然它會把 app 送來的提示詞當成可疑的貼上內容。
// 只用英數和空白，萬一要走 shell 也不會被引號弄壞
const SYSTEM =
  'You are the backend of a travel planning app. The user message is the full request built by the app itself. Follow it and output exactly the JSON object it asks for, with no other text.';

function cliArgs() {
  const args = ['-p', '--output-format', 'text', '--no-session-persistence', '--strict-mcp-config'];
  if (MODEL) args.push('--model', MODEL);
  args.push('--system-prompt', SYSTEM, '--tools', '');
  return args;
}

// ---------- 找 claude ----------
// Windows 上 npm 裝的 claude 是 claude.cmd，Node 不准不開 shell 直接跑 .cmd。
// 優先從 claude.cmd 找到它背後的 cli.js，用 node 直接跑（不經 shell，參數原樣傳）；
// 找不到才退回 shell: true，而且命令字串裡只有固定的參數，使用者的內容一律走 stdin。
function whereAll(name) {
  try {
    const out = execFileSync(IS_WIN ? 'where' : 'which', IS_WIN ? [name] : ['-a', name], {
      encoding: 'utf8',
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return out.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  } catch {
    return [];
  }
}

function resolveClaude() {
  if (!IS_WIN) return { file: 'claude', pre: [], shell: false, how: 'claude' };
  const found = whereAll('claude');
  const exe = found.find((p) => p.toLowerCase().endsWith('.exe'));
  if (exe) return { file: exe, pre: [], shell: false, how: exe };
  const cmd = found.find((p) => p.toLowerCase().endsWith('.cmd'));
  if (cmd) {
    const dir = path.dirname(cmd);
    let js = '';
    try {
      const text = fs.readFileSync(cmd, 'utf8');
      const m = text.match(/%dp0%\\([^"]+?\.js)/i);
      if (m) js = path.join(dir, m[1]);
    } catch {
      /* 讀不到就用下面的預設位置 */
    }
    if (!js || !fs.existsSync(js)) js = path.join(dir, 'node_modules', '@anthropic-ai', 'claude-code', 'cli.js');
    if (fs.existsSync(js)) {
      const localNode = path.join(dir, 'node.exe');
      const node = fs.existsSync(localNode) ? localNode : process.execPath;
      return { file: node, pre: [js], shell: false, how: `node ${js}` };
    }
  }
  return { file: 'claude', pre: [], shell: true, how: 'claude（經 cmd.exe）' };
}

const CLAUDE = resolveClaude();

// 只在 shell 模式用：把固定參數拼成命令字串（不含任何使用者內容）
function shellLine(args) {
  return ['claude', ...args.map((a) => (a === '' ? '""' : /[\s"]/.test(a) ? `"${a}"` : a))].join(' ');
}

function childEnv() {
  const env = { ...process.env };
  // 從 Claude Code 裡面開這支時，別讓子程序以為自己是巢狀的 session
  delete env.CLAUDECODE;
  delete env.CLAUDE_CODE_ENTRYPOINT;
  return env;
}

function startCli(args) {
  fs.mkdirSync(CWD, { recursive: true });
  const opts = { cwd: CWD, env: childEnv(), windowsHide: true };
  if (CLAUDE.shell) return spawn(shellLine(args), { ...opts, shell: true });
  return spawn(CLAUDE.file, [...CLAUDE.pre, ...args], opts);
}

// 砍整棵程序樹（shell 模式下 child 是 cmd.exe，只砍它的話 claude 會留著）
function killTree(child) {
  if (!child || child.exitCode !== null || child.killed) return;
  if (IS_WIN && child.pid) {
    try {
      execFileSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true });
      return;
    } catch {
      /* 退回下面 */
    }
  }
  child.kill('SIGKILL');
}

function cliVersion() {
  return new Promise((resolve) => {
    let out = '';
    let child;
    try {
      child = startCli(['--version']);
    } catch {
      return resolve('');
    }
    const timer = setTimeout(() => (killTree(child), resolve('')), 20 * 1000);
    child.stdout.on('data', (d) => (out += d));
    child.on('error', () => (clearTimeout(timer), resolve('')));
    child.on('close', (code) => (clearTimeout(timer), resolve(code === 0 ? out.trim() : '')));
    child.stdin.end();
  });
}

// ---------- 跑一次 CLI（同一時間只跑一個） ----------
let running = null;
let queue = Promise.resolve();
let waiting = 0;

class CliError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function runCli(prompt) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = startCli(cliArgs());
    } catch (e) {
      return reject(new CliError(502, String(e.message || e).slice(0, 200)));
    }
    running = child;
    let out = '';
    let err = '';
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      killTree(child);
    }, TIMEOUT_MS);
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (err += d));
    child.stdin.on('error', () => {
      /* CLI 先結束時 stdin 會斷，交給 close 處理 */
    });
    child.on('error', (e) => {
      clearTimeout(timer);
      running = null;
      reject(new CliError(502, String(e.message || e).slice(0, 200)));
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      running = null;
      if (timedOut) return reject(new CliError(504, 'timeout'));
      const text = out.trim();
      if (code !== 0) {
        const msg = (err.trim() || text || `claude 結束碼 ${code}`).slice(0, 200);
        return reject(new CliError(502, msg));
      }
      if (!text) return reject(new CliError(502, (err.trim() || 'claude 沒有回任何文字').slice(0, 200)));
      resolve(text);
    });
    child.stdin.end(prompt, 'utf8');
  });
}

function enqueue(task) {
  waiting += 1;
  const p = queue.then(
    () => {
      waiting -= 1;
      return task();
    },
    () => {
      waiting -= 1;
      return task();
    },
  );
  queue = p.catch(() => {});
  return p;
}

// ---------- HTTP ----------
function stamp() {
  return new Date().toLocaleTimeString('zh-TW', { hour12: false });
}

function send(res, code, obj) {
  if (res.writableEnded || res.destroyed) return;
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function tokenOk(t) {
  if (typeof t !== 'string' || t.length !== TOKEN.length) return false;
  return crypto.timingSafeEqual(Buffer.from(t), Buffer.from(TOKEN));
}

let CLI_VERSION = '';

function handleAsk(req, res) {
  const chunks = [];
  let size = 0;
  let tooBig = false;
  req.on('data', (d) => {
    if (tooBig) return;
    size += d.length;
    if (size > BODY_MAX) {
      tooBig = true;
      send(res, 413, { error: 'body 超過 1MB' });
      req.resume();
      return;
    }
    chunks.push(d);
  });
  req.on('end', async () => {
    if (tooBig) return;
    let prompt = '';
    try {
      const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (data && typeof data.prompt === 'string') prompt = data.prompt;
    } catch {
      /* 下面一起擋 */
    }
    if (!prompt.trim()) return send(res, 400, { error: '要給 {"prompt": "..."}' });

    const ahead = waiting + (running ? 1 : 0);
    console.log(`[${stamp()}] 收到一句（${prompt.length} 字）${ahead ? `，前面還有 ${ahead} 句在排` : ''}`);
    const t0 = Date.now();
    try {
      const text = await enqueue(() => {
        // 排隊時 app 那頭已經放棄了，就不用再跑
        if (res.destroyed) throw new CliError(499, 'app 已經斷線');
        return runCli(prompt);
      });
      const sec = ((Date.now() - t0) / 1000).toFixed(1);
      console.log(`[${stamp()}] 回了，花了 ${sec} 秒，成功`);
      send(res, 200, { text });
    } catch (e) {
      const sec = ((Date.now() - t0) / 1000).toFixed(1);
      const status = e instanceof CliError ? e.status : 502;
      const why = status === 504 ? '超過 170 秒' : status === 499 ? 'app 已經斷線，沒跑' : `CLI 失敗（${status}）`;
      console.log(`[${stamp()}] 花了 ${sec} 秒，失敗：${why}`);
      send(res, status === 499 ? 502 : status, { error: status === 504 ? 'timeout' : String(e.message || e).slice(0, 200) });
    }
  });
  req.on('error', () => {
    /* 連線斷掉就算了 */
  });
}

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url || '/', 'http://localhost');
  } catch {
    return send(res, 400, { error: '網址看不懂' });
  }
  if (!tokenOk(url.searchParams.get('t'))) {
    req.resume();
    return send(res, 401, { error: '密碼不對' });
  }
  if (url.pathname === '/ping') {
    if (req.method !== 'GET') return send(res, 405, { error: '只收 GET' });
    return send(res, 200, { ok: true, name: os.hostname(), cli: CLI_VERSION });
  }
  if (url.pathname === '/ask') {
    if (req.method !== 'POST') {
      req.resume();
      return send(res, 405, { error: '只收 POST' });
    }
    return handleAsk(req, res);
  }
  req.resume();
  send(res, 404, { error: '只有 /ping 和 /ask' });
});
// CLI 最多跑 170 秒，排隊還要再等，別讓 Node 自己先把連線斷掉
server.requestTimeout = 0;
server.headersTimeout = 30 * 1000;

// ---------- 找區網 IP ----------
const VIRTUAL = /vethernet|virtualbox|vmware|vbox|hyper-v|wsl|docker|loopback|tailscale|zerotier|hamachi|vpn|tap|tun|utun|veth|br-|bridge|npcap/i;

function privateRank(ip) {
  if (ip.startsWith('192.168.')) return 0;
  if (ip.startsWith('10.')) return 1;
  const m = ip.match(/^172\.(\d+)\./);
  if (m && Number(m[1]) >= 16 && Number(m[1]) <= 31) return 2;
  return 9;
}

function lanIps() {
  const all = [];
  for (const [name, list] of Object.entries(os.networkInterfaces())) {
    for (const a of list || []) {
      const v4 = a.family === 'IPv4' || a.family === 4;
      if (!v4 || a.internal || a.address.startsWith('169.254.')) continue;
      all.push({ name, ip: a.address, rank: privateRank(a.address), virtual: VIRTUAL.test(name) });
    }
  }
  let pick = all.filter((x) => !x.virtual && x.rank < 9);
  if (!pick.length) pick = all.filter((x) => x.rank < 9);
  if (!pick.length) pick = all;
  return pick.sort((a, b) => a.rank - b.rank);
}

// ---------- 開機與關機 ----------
function printBanner() {
  const ips = lanIps();
  console.log('');
  console.log('蘿蔔旅行 × Claude CLI 轉接（開發測試用）');
  console.log(`叫 CLI 的方式：${CLAUDE.how}`);
  console.log(`Claude CLI：${CLI_VERSION || '（取不到版本，確認 claude 有裝好、有登入）'}`);
  console.log(`模型：${MODEL || 'CLI 預設'}`);
  console.log('');
  if (!ips.length) {
    console.log(`找不到區網 IP。這台電腦有連上 Wi-Fi 嗎？埠號 ${PORT}，密碼 ${TOKEN}`);
    return;
  }
  const urls = ips.map((x) => `http://${x.ip}:${PORT}/ask?t=${TOKEN}`);
  console.log('在 app 的「平常的我 → 連電腦的 Claude CLI」掃這個：');
  qrcode.generate(urls[0], { small: true }, (q) => console.log(q));
  ips.forEach((x, i) => console.log(`${urls[i]}   （${x.name}）`));
  console.log('');
  console.log('iPhone 跟這台電腦要連同一個 Wi-Fi；第一次會問要不要讓蘿蔔旅行找區網裝置，要按允許');
  console.log('按 Ctrl+C 結束');
  console.log('');
}

let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  console.log(`\n[${stamp()}] 收到結束，關掉中…`);
  if (running) killTree(running);
  server.close(() => process.exit(0));
  if (server.closeAllConnections) server.closeAllConnections();
  setTimeout(() => process.exit(0), 3000).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('SIGHUP', shutdown);

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') console.error(`埠號 ${PORT} 已經有人在用。關掉另一個，或用 PORT=8788 npm start 換一個`);
  else console.error(`伺服器開不起來：${e.message}`);
  process.exit(1);
});

CLI_VERSION = await cliVersion();
server.listen(PORT, '0.0.0.0', printBanner);
