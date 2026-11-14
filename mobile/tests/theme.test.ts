import assert from 'node:assert/strict';
import { test } from 'node:test';
import { auditTheme } from '@domy/design/src/theme/createTheme';
import { radishTheme } from '../src/theme';

test('蘿蔔橘淺深色的對比全部及格', () => {
  const issues = auditTheme(radishTheme);
  assert.deepEqual(issues, [], issues.map((i) => `${i.scheme} ${i.pair} = ${i.ratio}（要 ${i.min}）`).join('\n'));
});
