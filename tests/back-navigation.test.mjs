import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { BackNavigation } = await loadEts('common/BackNavigation.ets');

test('remote Back closes a panel, then walks Player → Detail → Search → home, consuming every press', () => {
  BackNavigation.clear();
  const paths = ['Search', 'Detail', 'Player'];
  let panel = true;
  let saved = 0;
  let root = 0;
  const pop = () => paths.pop();
  BackNavigation.register('Player', () => {
    if (panel) panel = false;
    else { saved++; pop(); }
  });
  const press = () => assert.equal(BackNavigation.dispatch(paths, pop, () => root++), true);
  press(); assert.equal(panel, false); assert.equal(paths.length, 3);
  press(); assert.equal(saved, 1); assert.deepEqual(paths, ['Search', 'Detail']);
  press(); assert.deepEqual(paths, ['Search']);
  press(); assert.deepEqual(paths, []);
  press(); press(); assert.equal(root, 2); assert.equal(saved, 1);
});

test('cached destination re-entry uses the newest handler and cannot call a hidden player', () => {
  BackNavigation.clear();
  const seen = [];
  BackNavigation.register('Player', () => seen.push('old'));
  BackNavigation.register('Player', () => seen.push('new'));
  BackNavigation.dispatch(['Player'], () => seen.push('pop'), () => seen.push('home'));
  BackNavigation.dispatch(['Detail'], () => seen.push('pop'), () => seen.push('home'));
  assert.deepEqual(seen, ['new', 'pop']);
  BackNavigation.clear();
  BackNavigation.dispatch(['Player'], () => seen.push('cleared'), () => {});
  assert.equal(seen.at(-1), 'cleared');
});
