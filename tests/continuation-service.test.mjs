import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { PlaybackContinuation: flow } = await loadEts('common/PlaybackContinuation.ets');
let permission = false;
let requestResult = -1;
globalThis.__continuationServiceKit = {
  abilityAccessCtrl: {
    GrantStatus: { PERMISSION_GRANTED: 0 },
    createAtManager: () => ({
      checkAccessTokenSync: () => permission ? 0 : -1,
      requestPermissionsFromUser: async () => { permission = requestResult === 0; return { authResults: [requestResult] }; }
    })
  },
  AbilityConstant: { ContinueState: { ACTIVE: 1, INACTIVE: 0 } }, flow
};
const { ContinuationService: service } = await loadEts('common/ContinuationService.ets', [
  [/^import .*;$/gm, ''],
  [/^/, 'const { abilityAccessCtrl, AbilityConstant, flow: PlaybackContinuation } = globalThis.__continuationServiceKit;\n']
]);
const flush = () => new Promise(resolve => setImmediate(resolve));

test('permission denial keeps migration unavailable; in-flight ACTIVE cannot win over leaving playback', async () => {
  const writes = [], complete = [];
  const context = { applicationInfo: { accessTokenId: 1 },
    setMissionContinueState: state => { writes.push(state); return new Promise(resolve => complete.push(resolve)); } };
  service.bind(context);
  assert.deepEqual(writes, [0]);
  const owner = flow.register(() => ({}), () => {});
  assert.equal(await service.enable(context), false);
  complete.shift()(); await flush();
  assert.deepEqual(writes, [0]);
  requestResult = 0;
  assert.equal(await service.enable(context), true);
  assert.deepEqual(writes, [0, 1]);
  flow.unregister(owner); // ACTIVE is still pending at this point.
  complete.shift()(); await flush();
  assert.deepEqual(writes, [0, 1, 0]);
  complete.shift()(); await flush();
  service.sync();
  assert.deepEqual(writes, [0, 1, 0]);
});
