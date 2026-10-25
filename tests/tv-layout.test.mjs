import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { TvLayout } = await loadEts('common/TvLayout.ets');

test('TV and tablet landscape split keeps room for summary actions and readable episode targets', () => {
  for (const [width, height] of [[840, 600], [960, 540], [1280, 720], [1920, 1080]]) {
    assert.equal(TvLayout.isLandscape(width, height), true);
    const side = TvLayout.sidebarWidth(width);
    assert.ok(side >= 360 && side <= 460);
    const available = width - side - 120;
    const count = TvLayout.columns(available, 132, 8).split(' ').length;
    assert.ok(count >= 2 && count <= 8);
    assert.ok((available - (count - 1) * 8) / count >= 132);
  }
});

test('phone, portrait, and unmeasured windows retain compact layout; episode columns remain bounded', () => {
  for (const [w, h] of [[0, 0], [392, 800], [800, 1280], [1280, 1920], [800, 600]]) {
    assert.equal(TvLayout.isLandscape(w, h), false);
  }
  assert.equal(TvLayout.columns(360, 84, 8), '1fr 1fr 1fr 1fr');
  assert.equal(TvLayout.columns(4000, 140, 8).split(' ').length, 8);
  assert.equal(TvLayout.columns(-32, 84, 8), '1fr');
});
