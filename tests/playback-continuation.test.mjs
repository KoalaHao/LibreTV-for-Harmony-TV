import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { PlaybackContinuation: flow } = await loadEts('common/PlaybackContinuation.ets');
const state = (id = 'incoming-1') => ({ schema: 1, transferId: id,
  sourceKey: 'source-A', vodId: 'film-42', episode: 7, episodeName: '第八集',
  title: '测试影片 & 第二季', pic: 'https://example.test/poster.jpg', lineIndex: 2,
  positionMs: 742123, speed: 1.25, playing: true, episodeUrl: 'https://example.test/8.m3u8?auth=temporary' });

test('transfer protocol round trips exact content, episode, line, position, speed and paused state', () => {
  const value = { ...state(), playing: false };
  assert.deepEqual(flow.parse(JSON.stringify(value)), value);
  assert.equal(flow.parse(JSON.stringify({ ...value, unrelated: { password: 'not-forwarded' } })).unrelated, undefined);
});

test('malformed, unsupported or excessive transfer data never launches a player', () => {
  const invalid = [null, {}, [], { ...state(), schema: 2 }, { ...state(), episode: -1 },
    { ...state(), episode: 1.5 }, { ...state(), lineIndex: -1 }, { ...state(), positionMs: Infinity },
    { ...state(), positionMs: -100 }, { ...state(), positionMs: 1e12 }, { ...state(), speed: 4 },
    { ...state(), playing: 'true' }, { ...state(), transferId: '' }, { ...state(), vodId: '' },
    { ...state(), title: 'x'.repeat(513) }, { ...state(), episodeUrl: 'file:///data/storage/private.ts' },
    { ...state(), episodeUrl: 'fd://123' }, { ...state(), episodeUrl: 'http://127.0.0.1:9000/media' }];
  for (const value of invalid) assert.equal(flow.parse(JSON.stringify(value)), null);
  assert.equal(flow.parse('{broken'), null);
  assert.equal(flow.parse(' '.repeat(24577)), null);
});

test('URLs may reference a LAN media server but cannot reference the sending device loopback or sandbox', () => {
  for (const url of ['https://example.test/v.mp4', 'http://192.0.2.10:8000/video', 'https://[2001:db8::1]/v']) {
    assert.equal(flow.remoteUrl(url), true, url);
  }
  for (const url of ['http://localhost/v', 'http://LOCALHOST:8080/v', 'http://a.localhost/v',
    'http://127.1.2.3/v', 'http://[::1]:123/v', 'http://0.0.0.0/v', 'fd://3', 'https://', 'https://host/a b']) {
    assert.equal(flow.remoteUrl(url), false, url);
  }
});

test('cold-start inbox delivers only after a receiver attaches and coalesces repeated launches', () => {
  flow.detach();
  assert.equal(flow.receive(JSON.stringify(state('cold-1'))), true);
  assert.equal(flow.receive(JSON.stringify(state('cold-2'))), true);
  const received = [];
  flow.attach(s => received.push(s));
  assert.deepEqual(received.map(s => s.transferId), ['cold-2']);
  flow.receive(JSON.stringify(state('cold-2')));
  flow.attach(s => received.push(s));
  assert.equal(received.length, 1);
  flow.receive(JSON.stringify(state('warm-1')));
  assert.equal(received.at(-1).transferId, 'warm-1');
  assert.equal(flow.receive('invalid'), false);
  assert.equal(received.length, 2);
  flow.detach();
});

test('capture reads the latest playback position without pausing the source; stale page cleanup cannot clear a new owner', () => {
  let position = 1000;
  let stops = 0;
  const old = flow.register(() => ({ ...state(''), positionMs: position }), () => stops++);
  position = 123456;
  const value = flow.parse(flow.capture());
  assert.equal(value.positionMs, 123456);
  assert.ok(value.transferId.length > 0);
  assert.equal(stops, 0);
  const current = flow.register(() => state(''), () => stops += 10);
  flow.unregister(old);
  assert.equal(flow.available(), true);
  flow.stopCurrent();
  assert.equal(stops, 10);
  flow.unregister(current);
  assert.equal(flow.capture(), null);
  flow.stopCurrent(); assert.equal(stops, 10);
});

test('offline/unready providers and failed state reads reject continuation without interrupting playback', () => {
  let stop = 0;
  let owner = flow.register(() => null, () => stop++);
  assert.equal(flow.available(), false);
  assert.equal(flow.capture(), null);
  flow.unregister(owner);
  owner = flow.register(() => { throw new Error('released'); }, () => stop++);
  assert.equal(flow.available(), false);
  assert.equal(flow.capture(), null);
  assert.equal(stop, 0);
  flow.unregister(owner);
});

test('late duplicate warm intents cannot replay an older film after a newer transfer', () => {
  const seen = [];
  flow.attach(s => seen.push(s.transferId));
  flow.receive(JSON.stringify(state('dedupe-A')));
  flow.receive(JSON.stringify(state('dedupe-B')));
  flow.receive(JSON.stringify(state('dedupe-A')));
  assert.deepEqual(seen, ['dedupe-A', 'dedupe-B']);
  flow.detach();
});

test('Ability shutdown releases the native owner without popping a navigation stack', () => {
  let navigation = 0, release = 0;
  flow.register(() => state(''), () => navigation++, () => release++);
  flow.shutdown(); flow.shutdown();
  assert.equal(navigation, 0);
  assert.equal(release, 1);
  assert.equal(flow.available(), false);
  assert.equal(flow.capture(), null);
});
