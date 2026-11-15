// node up.mjs upload   → 只上傳 Expo Go（不計模擬器時間）
// node up.mjs boot     → 開模擬器並裝好 Expo Go，把連線資訊寫進 state.json
import fs from 'node:fs';
import path from 'node:path';
import { HERE, STATE, lim } from './lib.mjs';

const ASSET = 'expo-go-58.0.7-sim.zip';
const l = lim();
const mode = process.argv[2];

if (mode === 'upload') {
  const t = Date.now();
  const a = await l.assets.getOrUpload({ path: path.join(HERE, '..', 'expogo', 'ExpoGo.zip'), name: ASSET, platform: 'ios', kind: 'App' });
  console.log('asset ok', a?.id ?? a?.name ?? Object.keys(a ?? {}), Math.round((Date.now() - t) / 1000) + 's');
} else if (mode === 'boot') {
  const t = Date.now();
  const inst = await l.iosInstances.create({
    wait: true,
    spec: {
      model: 'iphone',
      inactivityTimeout: '6m',
      hardTimeout: '30m',
      initialAssets: [{ kind: 'App', source: 'AssetName', assetName: ASSET, launchMode: 'RelaunchIfRunning' }],
    },
  });
  fs.writeFileSync(STATE, JSON.stringify({ id: inst.metadata.id, apiUrl: inst.status.apiUrl, token: inst.status.token, at: new Date().toISOString() }));
  console.log('booted', inst.metadata.id, inst.status.state, Math.round((Date.now() - t) / 1000) + 's');
} else if (mode === 'down') {
  const st = JSON.parse(fs.readFileSync(STATE, 'utf8'));
  await l.iosInstances.delete(st.id);
  console.log('deleted', st.id, 'ran since', st.at, 'now', new Date().toISOString());
} else if (mode === 'list') {
  const page = await l.iosInstances.list({});
  const items = page.items ?? page.data ?? page;
  for (const i of items) console.log(i.metadata?.id, i.status?.state, i.metadata?.createdAt, JSON.stringify(i.metadata?.labels ?? {}));
  console.log('count', items.length);
}
process.exit(0);
