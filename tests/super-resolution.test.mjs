import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';

const players = [];
globalThis.__testMedia = {
  createAVPlayer: async () => players.shift(),
  createMediaSourceWithUrl: (url, headers) => ({ url, headers })
};
const { AvPlayerController } = await loadEts('player/AvPlayerController.ets', [
  ["import { media } from '@kit.MediaKit';", 'const media = globalThis.__testMedia;'],
  ["import { BusinessError } from '@kit.BasicServicesKit';", '']
]);
function mockPlayer({ srListener = true, srSource = true, fatalSource = false } = {}) {
  return {
    state: 'idle', listeners: new Map(), strategies: [],
    on(event, callback) {
      if (event === 'superResolutionChanged' && !srListener) throw Object.assign(new Error('unsupported'), { code: 801 });
      this.listeners.set(event, callback);
    },
    setMediaSource(source, strategy) {
      this.strategies.push({ ...strategy });
      if (strategy.enableSuperResolution && !srSource) {
        if (fatalSource) this.state = 'error';
        throw Object.assign(new Error('unsupported'), { code: 5410003 });
      }
      this.state = 'initialized';
    },
    prepare() { this.prepared = true; },
    reset() { this.state = 'idle'; },
    release() { this.state = 'released'; }
  };
}
async function setup(options, enabled = true) {
  const native = mockPlayer(options);
  players.push(native);
  const controller = new AvPlayerController();
  const states = [], errors = [];
  controller.onSuperResolutionState = s => states.push(s);
  controller.onError = e => errors.push(e);
  controller.configureSuperResolution(enabled);
  assert.equal(await controller.create('surface'), true);
  return { native, controller, states, errors };
}

test('each source requests SR before prepare; only the native callback confirms it is active', async () => {
  const { native, controller, states } = await setup();
  assert.equal(await controller.playUrl('https://example.test/1.m3u8', {}, 5000), true);
  assert.equal(native.strategies[0].enableSuperResolution, true);
  assert.equal(states.at(-1), 'requesting');
  native.listeners.get('superResolutionChanged')(true);
  assert.equal(states.at(-1), 'active');
  native.listeners.get('superResolutionChanged')(false);
  assert.equal(states.at(-1), 'inactive'); // e.g. 60 fps or fast playback
  native.state = 'playing';
  await controller.playUrl('https://example.test/2.m3u8', {});
  assert.equal(native.strategies[1].enableSuperResolution, true);
  assert.equal(states.at(-1), 'requesting');
});

test('unsupported strategy falls back to ordinary playback and subsequent episodes stay playable', async () => {
  const { native, controller, states, errors } = await setup({ srSource: false });
  assert.equal(await controller.playUrl('https://example.test/movie.mp4', {}), true);
  assert.equal(native.prepared, true);
  assert.deepEqual(native.strategies.map(s => !!s.enableSuperResolution), [true, false]);
  assert.equal(states.at(-1), 'unavailable');
  await controller.playUrl('https://example.test/next.mp4', {});
  assert.equal(native.strategies.at(-1).enableSuperResolution, undefined);
  assert.deepEqual(errors, []);
});

test('unsupported listener and disabled setting both preserve ordinary playback', async () => {
  for (const [options, enabled, state] of [[{ srListener: false }, true, 'unavailable'], [{}, false, 'off']]) {
    const { native, controller, states, errors } = await setup(options, enabled);
    assert.equal(await controller.playUrl('https://example.test/movie.mp4', {}), true);
    assert.equal(native.strategies[0].enableSuperResolution, undefined);
    assert.equal(states.at(-1), state);
    assert.deepEqual(errors, []);
  }
});

test('ordinary media errors still reach UI, and callbacks from released instances are ignored', async () => {
  const { native, controller, states, errors } = await setup();
  native.listeners.get('error')({ code: 5400103 });
  assert.equal(errors.length, 1);
  controller.release();
  const count = states.length;
  native.listeners.get('superResolutionChanged')(true);
  assert.equal(states.length, count);
});

test('SR rejection that poisons the native instance recreates it before ordinary playback', async () => {
  const { native, controller, states, errors } = await setup({ srSource: false, fatalSource: true });
  const fallback = mockPlayer();
  players.push(fallback);
  assert.equal(await controller.playUrl('https://example.test/movie.mp4', {}), true);
  assert.equal(native.state, 'released');
  assert.equal(fallback.prepared, true);
  assert.equal(fallback.strategies[0].enableSuperResolution, undefined);
  assert.equal(states.at(-1), 'unavailable');
  assert.deepEqual(errors, []);
});
