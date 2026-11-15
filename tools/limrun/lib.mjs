import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import Limrun, { Ios } from '@limrun/api';

export const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
export const STATE = path.join(HERE, 'state.json');
export const SHOTS = path.join(HERE, 'shots');

export function apiKey() {
  if (process.env.LIM_API_KEY) return process.env.LIM_API_KEY;
  const y = fs.readFileSync(path.join(os.homedir(), '.lim', 'config.yaml'), 'utf8');
  const m = y.match(/^api-key:\s*["']?([^"'\s]+)/m);
  if (!m) throw new Error('no api-key in ~/.lim/config.yaml');
  return m[1];
}
export const lim = () => new Limrun({ apiKey: apiKey() });

export async function client() {
  const st = JSON.parse(fs.readFileSync(STATE, 'utf8'));
  return Ios.createInstanceClient({ apiUrl: st.apiUrl, token: st.token });
}

/** 把元素樹攤平成「有標籤的東西」清單 */
export function flat(tree, out = []) {
  for (const n of tree ?? []) {
    const label = n.AXLabel || n.title || n.AXValue;
    if (label) out.push({ t: n.type, l: String(label).replace(/\s+/g, ' ').slice(0, 70), x: Math.round(n.frame.x + n.frame.width / 2), y: Math.round(n.frame.y + n.frame.height / 2), en: n.enabled });
    flat(n.children, out);
  }
  return out;
}
