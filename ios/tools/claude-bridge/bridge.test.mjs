// 不叫真的 claude、不花額度：PATH 裡放一支假的 claude，看轉接程式交給它什麼、怎麼回手機。
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'radish-bridge-test-'));
const SECRET_PATH = path.join(DIR, 'somewhere', 'private.txt');
const STUB = `
if (process.argv.includes('--version')) { console.log('0.0.0 (stub)'); process.exit(0); }
let stdin = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => (stdin += d));
process.stdin.on('end', () => {
  if (stdin.includes('FAIL')) { console.error('cannot open ' + ${JSON.stringify(SECRET_PATH)}); process.exit(1); }
  const out = { stdin, args: process.argv.slice(2), files: require('fs').readdirSync('.'), env: process.env };
  setTimeout(() => console.log(JSON.stringify(out)), stdin.includes('SLOW') ? 1500 : 0);
});
`;

let bridge;
let base;
let token;

async function freePort() {
  const s = net.createServer().listen(0);
  await once(s, 'listening');
  const { port } = s.address();
  s.close();
  await once(s, 'close');
  return port;
}

function ask(prompt, t = token) {
  return fetch(`${base}/ask?t=${encodeURIComponent(t)}`, { method: 'POST', body: JSON.stringify({ prompt }) });
}

async function seen(prompt) {
  const r = await ask(prompt);
  assert.equal(r.status, 200);
  return JSON.parse((await r.json()).text);
}

before(async () => {
  if (process.platform === 'win32') {
    fs.writeFileSync(path.join(DIR, 'stub.js'), STUB);
    fs.writeFileSync(path.join(DIR, 'claude.cmd'), '@"%dp0%\\stub.js" %*\r\n');
  } else {
    fs.writeFileSync(path.join(DIR, 'claude'), `#!/usr/bin/env node\n${STUB}`, { mode: 0o755 });
  }
  const pathKey = Object.keys(process.env).find((k) => k.toUpperCase() === 'PATH') || 'PATH';
  const sys = process.platform === 'win32' ? path.join(process.env.SystemRoot, 'System32') : '/usr/bin:/bin';
  const port = await freePort();
  base = `http://127.0.0.1:${port}`;
  bridge = spawn(process.execPath, [path.join(HERE, 'bridge.mjs')], {
    env: {
      ...process.env,
      [pathKey]: [DIR, sys, path.dirname(process.execPath)].join(path.delimiter),
      PORT: String(port),
      TEMP: DIR,
      TMP: DIR,
      TMPDIR: DIR,
      CLAUDE_MODEL: '',
      ANTHROPIC_API_KEY: 'should-not-pass',
      SOME_OTHER_SECRET: 'should-not-pass',
    },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  let out = '';
  bridge.stdout.setEncoding('utf8');
  if (process.env.SHOW_LOG) bridge.stdout.pipe(process.stderr);
  await new Promise((resolve, reject) => {
    bridge.stdout.on('data', (d) => {
      out += d;
      token = /(?:t=|密碼 )([0-9a-f]{32})/.exec(out)?.[1];
      if (token) resolve();
    });
    bridge.on('exit', () => reject(new Error(`bridge 沒開起來：${out}`)));
  });
});

after(async () => {
  bridge.kill();
  await once(bridge, 'exit');
  fs.rmSync(DIR, { recursive: true, force: true });
});

test('半形 @ 不管在哪都換成全形，開頭的 / ! # 也換掉', async () => {
  assert.equal((await seen('@C:\\a.txt 念 x@"b c" a@b\n@/etc/hosts')).stdin, '＠C:\\a.txt 念 x＠"b c" a＠b\n＠/etc/hosts');
  assert.equal((await seen('/help 1/2')).stdin, '／help 1/2');
  assert.equal((await seen('\uFEFF \u200B\n!ls')).stdin, '！ls');
  assert.equal((await seen('#/記住 #1')).stdin, '＃／記住 #1');
  assert.equal((await seen('第二天 6/10 太滿！')).stdin, '第二天 6/10 太滿！');
});

test('CLI 拿到的參數、環境變數、資料夾', async () => {
  const s = await seen('你好');
  assert.equal(s.args[s.args.indexOf('--tools') + 1], '');
  assert.equal(s.args[s.args.indexOf('--setting-sources') + 1], '');
  for (const f of ['--strict-mcp-config', '--disable-slash-commands', '--no-session-persistence']) assert.ok(s.args.includes(f), f);
  assert.deepEqual(s.files, []);
  assert.equal(s.env.CLAUDE_CODE_DISABLE_ATTACHMENTS, '1');
  assert.equal(s.env.CLAUDE_CODE_DISABLE_CLAUDE_MDS, '1');
  assert.ok(!JSON.stringify(s.env).includes('should-not-pass'));
});

test('密碼不對回 401，奇怪的字也不會讓程式掛掉', async () => {
  for (const t of ['', 'x', 'é'.repeat(32), '蘿'.repeat(32), '0'.repeat(32), token + '0']) {
    assert.equal((await fetch(`${base}/ping?t=${encodeURIComponent(t)}`)).status, 401, t);
  }
  assert.equal((await fetch(`${base}/ping`)).status, 401);
  assert.equal((await fetch(`${base}/ping?t=${token}`)).status, 200);
});

test('別的路徑 404、方法不對 405、內容不對 400、太大 413', async () => {
  assert.equal((await fetch(`${base}/etc?t=${token}`)).status, 404);
  assert.equal((await fetch(`${base}/ask?t=${token}`)).status, 405);
  for (const body of ['', 'null', '[]', '{"prompt":1}', '{"prompt":"  "}']) {
    assert.equal((await fetch(`${base}/ask?t=${token}`, { method: 'POST', body })).status, 400, body);
  }
  assert.equal((await ask('a'.repeat(1024 * 1024 + 1))).status, 413);
});

test('CLI 失敗時手機拿不到路徑', async () => {
  const r = await ask('FAIL');
  assert.equal(r.status, 502);
  assert.ok(!(await r.text()).includes('private.txt'));
});

test('排太多句回 429，前面的照樣回', async () => {
  const codes = await Promise.all(
    Array.from({ length: 6 }, async (_, i) => {
      await new Promise((ok) => setTimeout(ok, i * 100));
      return (await ask('SLOW')).status;
    }),
  );
  assert.deepEqual(codes, [200, 200, 200, 429, 429, 429]);
});
