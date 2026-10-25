import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { TvFeedDataSource: Feed } = await loadEts('model/TvFeedDataSource.ets', [[/^import .*;$/gm, '']]);
const items = n => Array.from({length:n},(_,i)=>({id:String(i),title:'片名'+i,cover:'https://image.test/'+i,isTv:false}));
test('appending a page preserves complete row identities and replaces the formerly partial row', () => {
 const feed=new Feed();feed.setItems(items(20));
 const first=Array.from({length:feed.totalCount()},(_,i)=>feed.getData(i).key);
 feed.setItems(items(40));
 assert.deepEqual([1,2,3].map(i=>feed.getData(i).key),first.slice(1,4));
 assert.notEqual(feed.getData(4).key,first[4]);
 assert.equal(feed.getData(7).items.length,4);
 assert.equal(feed.getData(8).kind,'footer');
});
test('filter replacement cannot reuse another film row, and header/footer survive empty results', () => {
 const feed=new Feed();feed.setItems(items(6));const old=feed.getData(1).key;
 const next=items(6);next[0].cover='https://image.test/replaced';feed.setItems(next);
 assert.notEqual(feed.getData(1).key,old);
 feed.setItems([]);assert.equal(feed.totalCount(),2);
 assert.equal(feed.getData(0).kind,'header');assert.equal(feed.getData(1).kind,'footer');
});
test('listeners are notified once per data update and released on unmount', () => {
 const feed=new Feed();let updates=0;const listener={onDataReloaded(){updates++;}};
 feed.registerDataChangeListener(listener);feed.registerDataChangeListener(listener);
 feed.setItems(items(1000));assert.equal(updates,1);assert.equal(feed.totalCount(),169);
 feed.unregisterDataChangeListener(listener);feed.setItems([]);assert.equal(updates,1);
});
