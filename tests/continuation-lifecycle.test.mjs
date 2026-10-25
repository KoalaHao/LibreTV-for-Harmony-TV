import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { PlaybackContinuation: flow } = await loadEts('common/PlaybackContinuation.ets');
const constants = {
  LaunchReason: { CONTINUATION: 7 }, OnContinueResult: { AGREE: 0, REJECT: 1, MISMATCH: 2 }
};
let permission = true;
let binds = 0, genericLinks = 0;
const fakeContext = { getApplicationContext: () => ({ setColorMode() {} }) };
globalThis.__continuationAbilityKit = {
  UIAbility: class { context = fakeContext; }, AbilityConstant: constants,
  ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: 0 } },
  wantConstant: { Params: { SUPPORT_CONTINUE_PAGE_STACK_KEY: 'pageStack', SUPPORT_CONTINUE_SOURCE_EXIT_KEY: 'sourceExit' } },
  hilog: { info() {}, warn() {}, error() {} },
  Store: { shared: () => ({ init() {} }) }, SourceManager: { shared: () => ({ load() {} }) },
  SearchCacheStorage: { init() {} }, AdReportStorage: { init() {} },
  DownloadManager: { shared: () => ({ init() {}, resumeInterrupted() {} }) },
  DevicePolicy: { isTV: () => false },
  SettingsStore: { shared: () => ({ get: () => ({ themeMode: 'system' }) }) },
  PlaybackContinuation: flow,
  ContinuationService: { bind() { binds++; }, granted: () => permission, sync() {}, unbind() {} },
  ShareLink: { parse: () => null }, DeepLink: { push() { genericLinks++; } }
};
const { default: EntryAbility } = await loadEts('entryability/EntryAbility.ets', [
  [/^import .*;$/gm, ''],
  [/^/, 'const { UIAbility, AbilityConstant, ConfigurationConstant, wantConstant, hilog, Store, SearchCacheStorage, AdReportStorage, SourceManager, DownloadManager, SettingsStore, PlaybackContinuation, ContinuationService, ShareLink, DeepLink, DevicePolicy } = globalThis.__continuationAbilityKit;\n']
]);
const state = id => ({ schema: 1, transferId: id, sourceKey: 'src', vodId: '42', episode: 3,
  episodeName: '第四集', title: '影片', pic: '', lineIndex: 1, positionMs: 123450,
  speed: 1.5, playing: false, episodeUrl: 'https://example.test/4.m3u8' });

test('real Ability continuation callback rejects old/missing versions or permission and never pauses during preparation', () => {
  const ability = new EntryAbility();
  let stopped = 0;
  const owner = flow.register(() => state(''), () => stopped++);
  for (const version of [undefined, '1100104', 1100103]) assert.equal(ability.onContinue({ version }), 2);
  permission = false; assert.equal(ability.onContinue({ version: 1100104 }), 1);
  permission = true;
  const params = { version: 1100104 };
  assert.equal(ability.onContinue(params), 0);
  assert.equal(params.pageStack, false);
  assert.equal(params.sourceExit, true);
  assert.equal(flow.parse(params[flow.KEY]).positionMs, 123450);
  assert.equal(stopped, 0);
  flow.unregister(owner);
  assert.equal(ability.onContinue({ version: 1100104 }), 1);
});

test('cold onCreate queues state, warm onNewWant delivers once, malformed continuation cannot fall through to a generic link', () => {
  flow.detach();
  const ability = new EntryAbility();
  const want = { parameters: { [flow.KEY]: JSON.stringify(state('cold-lifecycle')) } };
  ability.onCreate(want, { launchReason: 7 });
  assert.equal(binds, 1);
  const seen = [];
  flow.attach(s => seen.push(s));
  assert.equal(seen[0].episode, 3);
  ability.onNewWant(want, { launchReason: 7 });
  assert.equal(seen.length, 1);
  ability.onNewWant({ parameters: { [flow.KEY]: JSON.stringify(state('warm-lifecycle')) } }, { launchReason: 7 });
  assert.equal(seen.length, 2);
  ability.onNewWant({ uri: 'libretv://play?src=bad&id=bad', parameters: { [flow.KEY]: 'broken' } }, { launchReason: 7 });
  assert.equal(seen.length, 2);
  assert.equal(genericLinks, 0);
  flow.detach();
});

test('restoring a cold WindowStage initializes the normal UI path, while warm restore preserves the mounted inbox', () => {
  const ability = new EntryAbility();
  let creates = 0;
  ability.onWindowStageCreate = () => { creates++; ability.win = {}; };
  ability.onWindowStageRestore({}); assert.equal(creates, 1);
  ability.onWindowStageRestore({}); assert.equal(creates, 1);
  ability.onWindowStageDestroy();
  ability.onWindowStageRestore({}); assert.equal(creates, 2);
});

test('successful source teardown releases its native player without navigating a destroyed UI', () => {
  let released = 0, navigation = 0;
  flow.register(() => state(''), () => navigation++, () => released++);
  new EntryAbility().onDestroy();
  assert.equal(released, 1);
  assert.equal(navigation, 0);
});
