import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { TvPlaybackGesture } = await loadEts('common/TvPlaybackGesture.ets');

test('normalized horizontal pans seek once when the gesture completes, independent of repeat updates', () => {
  const gesture = new TvPlaybackGesture();
  gesture.begin(true);
  for (const x of [10, 30, 70, 250]) gesture.update(x, 4);
  assert.equal(gesture.end(), 'forward');
  assert.equal(gesture.end(), 'none');
  gesture.begin(true); gesture.update(-160, 10);
  assert.equal(gesture.end(), 'backward');
});

test('vertical directions reveal controls; an open panel or visible controls retain native scrolling', () => {
  const gesture = new TvPlaybackGesture();
  for (const y of [-120, 120]) {
    gesture.begin(true); gesture.update(5, y);
    assert.equal(gesture.end(), 'controls');
  }
  gesture.begin(false); gesture.update(200, 0);
  assert.equal(gesture.end(), 'none');
});

test('pointer jitter, a gesture returning to its origin, and cancellation do not seek', () => {
  const gesture = new TvPlaybackGesture();
  gesture.begin(true); gesture.update(8, -12);
  assert.equal(gesture.end(), 'none');
  gesture.begin(true); gesture.update(200, 0); gesture.update(2, 0);
  assert.equal(gesture.end(), 'none');
  gesture.begin(true); gesture.update(200, 0); gesture.cancel();
  assert.equal(gesture.end(), 'none');
});

test('only a short Menu press opens playback actions; long/repeated/cancelled presses stay with the system', () => {
  const gesture = new TvPlaybackGesture();
  gesture.menuDown(1000); assert.equal(gesture.menuUp(1150), true);
  gesture.menuDown(2000); assert.equal(gesture.menuUp(2700), false);
  gesture.menuDown(3000); gesture.menuDown(3200); assert.equal(gesture.menuUp(3300), false);
  gesture.menuDown(4000); gesture.reset(); assert.equal(gesture.menuUp(4100), false);
  assert.equal(gesture.menuUp(5000), false);
});
