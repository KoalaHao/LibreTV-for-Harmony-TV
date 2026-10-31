import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';

const data = new Map();
globalThis.__historyStore = {
  Store: { shared: () => ({ getJson: key => data.get(key) || '', putJson: (key, value) => data.set(key, value) }) },
  EventBus: { emit() {} }, Events: { HISTORY_CHANGED: 'history' }
};
const { HistoryStore } = await loadEts('data/HistoryStore.ets', [
  [/^import .*;$/gm, ''],
  [/^/, 'const { Store, EventBus, Events } = globalThis.__historyStore;\n']
]);
test('persisted history preserves the selected playback line for direct source resume', () => {
  const store = HistoryStore.shared();
  store.saveProgress({ sourceKey: 'source', vodId: '42', name: '影片', sourceName: '源',
    episode: 2, lineIndex: 1, positionMs: 123456, durationMs: 600000, updatedAt: 1 });
  assert.equal(store.getHistory()[0].lineIndex, 1);
  assert.equal(store.getProgress('source', '42').lineIndex, 1);
  data.set('play_history', JSON.stringify([{ sourceKey: 'old', vodId: '1', episode: 0 }]));
  assert.equal(store.getProgress('old', '1').lineIndex, 0);
});
test('compensation belongs to its source and title history record and survives ordinary progress updates',()=>{
 data.clear();const store=HistoryStore.shared();
 const record=(sourceKey,vodId,gain)=>({sourceKey,vodId,name:'影片',sourceName:'源',episode:0,positionMs:5000,durationMs:60000,updatedAt:1,...(gain===undefined?{}:{loudnessGainDb:gain})});
 store.saveProgress(record('a','1',6));store.saveProgress(record('b','1',0));store.saveProgress(record('a','2',0));
 store.saveProgress(record('a','1'));
 assert.equal(store.getProgress('a','1').loudnessGainDb,6);
 assert.equal(store.getProgress('b','1').loudnessGainDb,0);assert.equal(store.getProgress('a','2').loudnessGainDb,0);
 store.saveProgress(record('a','1',0));assert.equal(store.getProgress('a','1').loudnessGainDb,0);
 store.saveProgress(record('a','2',999));assert.equal(store.getProgress('a','2').loudnessGainDb,0);
 store.clearHistory();assert.equal(store.getProgress('a','1'),null);
});
test('24 dB survives storage reload and ordinary updates without increasing legacy six dB records or other sources',()=>{
 data.clear();const store=HistoryStore.shared();
 const record=(sourceKey,gain)=>({sourceKey,vodId:'1',name:'影片',sourceName:'源',episode:0,positionMs:5000,durationMs:60000,updatedAt:1,...(gain===undefined?{}:{loudnessGainDb:gain})});
 store.saveProgress(record('boosted',24));store.saveProgress(record('legacy',6));store.saveProgress(record('other',0));
 const reload=new HistoryStore();reload.saveProgress(record('boosted'));
 assert.equal(reload.getProgress('boosted','1').loudnessGainDb,24);
 assert.equal(reload.getProgress('legacy','1').loudnessGainDb,6);assert.equal(reload.getProgress('other','1').loudnessGainDb,0);
 store.saveProgress(record('invalid',36));assert.equal(reload.getProgress('invalid','1').loudnessGainDb,0);
});
