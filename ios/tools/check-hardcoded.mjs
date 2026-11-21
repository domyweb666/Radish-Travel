// 畫面裡不准寫死色碼、字級、圓角、間距數字，一律用 T 和 C。
// 跑法：node ios/tools/check-hardcoded.mjs
// 真的只用一次的數值，在那一行寫 `// domy-ignore: 原因`。
// 不檢查的檔：代號檔、主題色、角色的向量圖（座標是內容，不是介面）。
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'Radish');
const SKIP = new Set(['DomyTokens.swift', 'Theme.swift', 'RadishBuddy.swift', 'RadishShape.swift', 'PullMoment.swift']);

const RULES = [
  [/0x[0-9A-Fa-f]{6}\b/, '色碼'],
  [/Color\(\s*(red|hue|white)\s*:/, '色碼'],
  [/\bColor\.(red|orange|yellow|green|blue|purple|pink|gray|black|white|brown|cyan|mint|teal|indigo)\b/, '系統色（改用 C）'],
  [/\.system\(\s*size\s*:/, '字級（改用 T.TypeScale）'],
  [/\.font\(\s*\.(largeTitle|title|title2|title3|headline|body|callout|subheadline|footnote|caption|caption2)\b/, '字級（改用 T.TypeScale 或 DomyText）'],
  [/cornerRadius\s*:\s*\d/, '圓角（改用 T.Radius）'],
  [/spacing\s*:\s*[1-9]\d*(\.\d+)?\s*[,)]/, '間距（改用 T.Space）'],
  [/\.padding\(\s*(\.\w+\s*,\s*)?[1-9]\d*(\.\d+)?\s*\)/, '間距（改用 T.Space）'],
  [/\.frame\([^)]*\b(width|height|minWidth|minHeight|maxWidth|maxHeight)\s*:\s*[1-9]\d*(\.\d+)?\s*[,)]/, '尺寸（改用 T.Size）'],
  [/lineWidth\s*:\s*\d/, '線寬（改用 T.Size.hairline）'],
  [/\.(easeInOut|easeOut|easeIn|linear)\s*\(/, '動畫曲線（改用 Motion 的代號，見 Kit/Motion.swift）'],
];

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else if (name.endsWith('.swift') && !SKIP.has(name)) out.push(full);
  }
  return out;
}

const hits = [];
for (const file of walk(root)) {
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    if (line.includes('domy-ignore')) return;
    const code = line.replace(/\/\/.*$/, '');
    for (const [re, what] of RULES) {
      if (re.test(code)) hits.push(`${relative(join(root, '..'), file)}:${i + 1} ${what}：${line.trim()}`);
    }
  });
}

if (hits.length) {
  console.error(`[check-hardcoded] 有 ${hits.length} 處寫死的數值：`);
  for (const h of hits) console.error('  ' + h);
  process.exit(1);
}
console.log('[check-hardcoded] 沒有寫死的數值');
