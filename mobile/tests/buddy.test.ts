import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BUDDY_ACTIONS, STILL_AT, blend, poseAt, skeleton, type Pose } from '../src/components/buddy/poses';

const nums = (p: Pose) => Object.entries(p).filter(([, v]) => typeof v === 'number') as Array<[string, number]>;

test('每個動作在任何時間點算出來的都是正常數字', () => {
  for (const a of BUDDY_ACTIONS) {
    for (let t = 0; t < 8; t += 0.07) {
      const p = poseAt(a, t, 'up');
      for (const [k, v] of nums(p)) assert.ok(Number.isFinite(v), `${a} t=${t.toFixed(2)} ${k}=${v}`);
      const k = skeleton(p);
      for (const pt of [k.hip, k.neck, ...k.legs.flat(), ...k.arms.flat()]) assert.ok(pt.every(Number.isFinite), `${a} 的骨架有壞掉的座標`);
    }
  }
});

test('不做成癮機制：沒有大慶祝和打瞌睡', () => {
  assert.ok(!(BUDDY_ACTIONS as string[]).includes('bigcheer'));
  assert.ok(!(BUDDY_ACTIONS as string[]).includes('sleep'));
});

test('每個動作都有「減少動態效果」用的靜止格', () => {
  for (const a of BUDDY_ACTIONS) assert.equal(typeof STILL_AT[a], 'number');
});

test('站著的時候腳踩在地上，歡呼時會離地', () => {
  const idle = skeleton(poseAt('idle', 1));
  assert.ok(Math.abs(idle.legs[0][2][1] - 380) < 6, `踝的高度 ${idle.legs[0][2][1]}`);
  assert.equal(idle.lift, 0);
  assert.ok(skeleton(poseAt('cheer', STILL_AT.cheer)).lift > 0.5);
});

test('換動作的過渡：頭尾分別等於前後兩個姿勢，中間在兩者之間', () => {
  const a = poseAt('idle', 1);
  const b = poseAt('wave', 0.2);
  assert.equal(blend(a, b, 0).rS, a.rS);
  assert.equal(blend(a, b, 1).rS, b.rS);
  const mid = blend(a, b, 0.5).rS;
  assert.ok(mid > Math.min(a.rS, b.rS) && mid < Math.max(a.rS, b.rS));
  assert.equal(blend(poseAt('idle', 1), poseAt('think', 1), 0.2).mouth, 'smile');
  assert.equal(blend(poseAt('idle', 1), poseAt('think', 1), 0.8).mouth, 'flat');
});
