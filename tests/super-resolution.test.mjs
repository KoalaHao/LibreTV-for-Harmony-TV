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
  ["import { audio } from '@kit.AudioKit';", 'const audio = { StreamUsage: { STREAM_USAGE_MOVIE: 3 } };'],
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
async function setup(options, enabled = true, allowRuntimeToggle = enabled) {
  const native = mockPlayer(options);
  players.push(native);
  const controller = new AvPlayerController();
  const states = [], errors = [];
  controller.onSuperResolutionState = s => states.push(s);
  controller.onError = e => errors.push(e);
  controller.configureSuperResolution(enabled, allowRuntimeToggle);
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

test('paused continuation prepares and seeks precisely without emitting play; normal resume retains autoplay', async () => {
  globalThis.__testMedia.SeekMode = { SEEK_CLOSEST: 2, SEEK_PREV_SYNC: 0 };
  for (const autoplay of [false, true]) {
    const { native, controller } = await setup({}, false);
    const calls = [];
    native.duration = 900000;
    native.setVolume = () => {};
    native.seek = (position, mode) => calls.push(['seek', position, mode]);
    native.play = () => calls.push(['play']);
    controller.configureAutoPlay(autoplay, true);
    await controller.playUrl('https://example.test/4.m3u8', {}, 123450);
    native.state = 'prepared';
    native.listeners.get('stateChange')('prepared');
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(calls[0], ['seek', 123450, 2]);
    assert.equal(calls.filter(c => c[0] === 'play').length, autoplay ? 1 : 0);
    assert.equal(native.strategies[0].showFirstFrameOnPrepare, true);
  }
});

test('source metadata uses selected video track and converts SDK frame-rate units', () => {
  const audio = { track_type: 0, track_index: 0, codec_mime: 'audio/mp4a-latm', bitrate: 128000 };
  const low = { track_type: 1, track_index: 1, width: 1280, height: 720, frame_rate: 2500, codec_mime: 'video/avc', bitrate: 2500000 };
  const high = { track_type: 1, track_index: 2, width: 1920, height: 1080, frame_rate: 2997, codec_mime: 'video/hevc' };
  assert.deepEqual(AvPlayerController.sourceVideoInfo([audio, low, high], [0, 2]),
    { width: 1920, height: 1080, fps: 29.97, codec: 'video/hevc', bitrate: 0 });
  assert.equal(AvPlayerController.sourceVideoInfo([audio, low], []).fps, 25);
  assert.deepEqual(AvPlayerController.sourceVideoInfo([low, high], []), AvPlayerController.emptyVideoInfo());
  assert.equal(AvPlayerController.sourceVideoInfo([{ ...low, width: NaN, bitrate: -1 }], []).width, 0);
});

test('source changes clear old metadata and released players cannot publish late track data', async () => {
  const { native, controller } = await setup({}, false);
  const info = [];
  controller.onVideoInfo = v => info.push(v);
  let resolveTracks;
  native.getTrackDescription = () => new Promise(resolve => { resolveTracks = resolve; });
  native.getSelectedTracks = async () => [1];
  native.setVolume = () => {};
  await controller.playUrl('https://example.test/one.m3u8', {});
  native.state = 'prepared';
  native.listeners.get('stateChange')('prepared');
  controller.release();
  resolveTracks([{ track_type: 1, track_index: 1, width: 1280, height: 720, frame_rate: 2500 }]);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(info, [AvPlayerController.emptyVideoInfo()]);
});

test('TV Off preference disables SR before prepare, then toggles the same stream without reset', async () => {
  const { native, controller, states } = await setup({}, false, true);
  const toggles = [];
  native.setSuperResolution = async enabled => {
    if (toggles.length === 0) assert.notEqual(native.prepared, true);
    toggles.push(enabled);
  };
  await controller.playUrl('https://example.test/ab.mp4', {}, 42000);
  assert.equal(native.strategies[0].enableSuperResolution, true);
  assert.deepEqual(toggles, [false]);
  native.state = 'playing';
  assert.equal(await controller.setSuperResolution(true), true);
  assert.equal(states.at(-1), 'enabled'); // Accepted command, with no new algorithm-state callback.
  native.listeners.get('superResolutionChanged')(true);
  assert.equal(states.at(-1), 'active');
  assert.equal(await controller.setSuperResolution(false), true);
  native.listeners.get('superResolutionChanged')(false);
  assert.equal(states.at(-1), 'off');
  assert.deepEqual(toggles, [false, true, false]);
  assert.equal(native.strategies.length, 1);
  assert.equal(native.state, 'playing');
});

test('SR switch rejection does not turn into a playback error or claim it succeeded', async () => {
  const { native, controller, states, errors } = await setup();
  native.state = 'playing';
  native.setSuperResolution = async () => { throw { code: 5410003 }; };
  assert.equal(await controller.setSuperResolution(false), false);
  assert.equal(states.at(-1), 'unavailable');
  assert.equal(native.state, 'playing');
  assert.deepEqual(errors, []);
});

test('when initial SR disable is unsupported, saved Off restarts preparation without the feature', async () => {
  const { native, controller, states } = await setup({}, false, true);
  native.setSuperResolution = async () => { throw { code: 5410004 }; };
  assert.equal(await controller.playUrl('https://example.test/plain.mp4', {}), true);
  assert.deepEqual(native.strategies.map(s => !!s.enableSuperResolution), [true, false]);
  assert.equal(native.prepared, true);
  assert.equal(states.at(-1), 'off');
});

test('native SR callback during the toggle remains authoritative over successful command completion', async () => {
  const { native, controller, states } = await setup();
  native.state = 'playing';
  native.setSuperResolution = async enabled => native.listeners.get('superResolutionChanged')(enabled);
  assert.equal(await controller.setSuperResolution(true), true);
  assert.equal(states.at(-1), 'active');
  assert.equal(await controller.setSuperResolution(false), true);
  assert.equal(states.at(-1), 'off');
});

test('missing runtime callback reparses the same source at the exact position and preserves paused/playing state', async () => {
  globalThis.__testMedia.SeekMode = { SEEK_CLOSEST: 2, SEEK_PREV_SYNC: 0 };
  for (const playing of [true, false]) {
    const { native, controller } = await setup();
    const calls = [];
    native.setSuperResolution = async () => {};
    native.setVolume = () => {};
    native.seek = (position, mode) => calls.push(['seek', position, mode]);
    native.play = () => calls.push(['play']);
    native.currentTime = 42420;
    native.duration = 900000;
    await controller.playUrl('https://example.test/same-source.mp4', {});
    native.state = playing ? 'playing' : 'paused';
    assert.equal(await controller.setSuperResolution(true, true), true);
    assert.equal(native.strategies.length, 2);
    native.state = 'prepared';
    native.listeners.get('stateChange')('prepared');
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(calls[0], ['seek', 42420, 2]);
    assert.equal(calls.filter(c => c[0] === 'play').length, playing ? 1 : 0);
  }
});

test('paused seek completion publishes the restored position without waiting for a playback timeUpdate', async () => {
  const { native, controller } = await setup();
  const positions = [];
  controller.onProgress = (position, duration) => positions.push([position, duration]);
  native.listeners.get('durationUpdate')(900000);
  native.state = 'paused';
  native.listeners.get('timeUpdate')(0);
  native.listeners.get('seekDone')(42420);
  assert.deepEqual(positions.at(-1), [42420, 900000]);
  controller.release();
  native.listeners.get('seekDone')(99999);
  assert.deepEqual(positions.at(-1), [42420, 900000]);
});
