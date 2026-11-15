// node run.mjs '<JSON 步驟陣列>'
// 步驟：{tree:1} {tap:'標籤'} {tapc:'標籤含'} {xy:[x,y]} {type:'字',enter:1} {shot:'名字'} {wait:毫秒}
//       {url:'exp://…'} {drag:[x1,y1,x2,y2]} {simctl:[…]} {key:'enter'} {kb:1}
import fs from 'node:fs';
import path from 'node:path';
import { SHOTS, client, flat } from './lib.mjs';

const steps = JSON.parse(process.argv[2]);
const c = await client();
fs.mkdirSync(SHOTS, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

for (const s of steps) {
  try {
    if (s.tree) {
      const items = flat(await c.elementTree(undefined, { visibleOnly: true }));
      const f = typeof s.tree === 'string' ? items.filter((i) => i.l.includes(s.tree)) : items;
      console.log('TREE ' + f.map((i) => `${i.t[0]}:${i.l}@${i.x},${i.y}${i.en ? '' : '(off)'}`).join(' | '));
    } else if (s.tap) {
      await c.tapElement({ AXLabel: s.tap }, { timeoutMs: s.timeout ?? 8000 });
      console.log('tap', s.tap);
    } else if (s.sel) {
      await c.tapElement(s.sel, { timeoutMs: s.timeout ?? 8000 });
      console.log('sel', JSON.stringify(s.sel));
    } else if (s.tapb) {
      await c.tapElement({ AXLabel: s.tapb, type: 'Button' }, { timeoutMs: s.timeout ?? 8000 });
      console.log('tapb', s.tapb);
    } else if (s.tapc) {
      await c.tapElement({ AXLabelContains: s.tapc }, { timeoutMs: s.timeout ?? 8000 });
      console.log('tapc', s.tapc);
    } else if (s.xy) {
      await c.tap(s.xy[0], s.xy[1]);
      console.log('xy', s.xy.join(','));
    } else if (s.type != null) {
      await c.typeText(s.type, !!s.enter);
      console.log('type', s.type);
    } else if (s.key) {
      await c.pressKey(s.key);
    } else if (s.kb) {
      await c.toggleKeyboard();
    } else if (s.shot) {
      const d = await c.screenshot({ format: 'jpeg', size: 'scaled' });
      const b64 = d.base64 ?? d.data ?? d.image ?? d;
      const file = path.join(SHOTS, s.shot + '.jpg');
      fs.writeFileSync(file, Buffer.from(typeof b64 === 'string' ? b64 : b64.base64, 'base64'));
      console.log('shot', file, d.width ?? '', d.height ?? '');
    } else if (s.wait) {
      await sleep(s.wait);
    } else if (s.url) {
      await c.openUrl(s.url);
      console.log('url', s.url);
    } else if (s.drag) {
      const [x1, y1, x2, y2] = s.drag;
      const n = 8;
      const acts = [{ type: 'touchDown', x: x1, y: y1 }];
      for (let i = 1; i <= n; i++) acts.push({ type: 'touchMove', x: x1 + ((x2 - x1) * i) / n, y: y1 + ((y2 - y1) * i) / n }, { type: 'wait', durationMs: 1 });
      acts.push({ type: 'touchUp', x: x2, y: y2 });
      await c.performActions(acts);
      console.log('drag');
    } else if (s.simctl) {
      const ex = c.simctl(s.simctl);
      const r = await ex.wait();
      console.log('simctl', JSON.stringify(r).slice(0, 300));
    }
  } catch (e) {
    console.log('FAIL', JSON.stringify(s), String(e?.message ?? e).slice(0, 200));
    if (!s.soft) break;
  }
}
c.disconnect?.();
process.exit(0);
