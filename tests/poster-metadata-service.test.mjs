import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { PosterCardData } = await loadEts('model/PosterCardData.ets');
globalThis.__posterData = PosterCardData;
const storage = new Map();
storage.set('poster_meta_index_v1', JSON.stringify(['10000000']));
storage.set('poster_meta_v1_10000000', JSON.stringify({info:{subjectId:'10000000',countries:['韩国'],genres:['剧情'],releaseDate:'2020',rating:'9.8',shortComments:900000}}));
globalThis.__posterStore = { shared: () => ({ getJson: k => storage.get(k) || '', putJson: (k,v) => storage.set(k,v), remove: k => storage.delete(k) }) };
const calls = [], held = [];
let mode = 'hold', active = 0, maxActive = 0;
globalThis.__posterHttp = { UA: 'test', getText: async (url, headers, timeout, usingCache) => {
  assert.equal(usingCache, false);
  calls.push(url);active++;maxActive=Math.max(maxActive,active);
  if (mode === 'hold') return new Promise(resolve => held.push({url, resolve: value => {active--;resolve(value);}}));
  active--;
  if (mode==='limited' && url.includes('subject_abstract')) return {ok:true,status:200,text:JSON.stringify({r:0,subject:{id:url.split('=').at(-1),is_tv:false,region:'美国',types:['剧情'],duration:'120分钟',release_year:'2026',rate:'8.9'}})};
  return {ok:false,status:mode==='limited'?400:404,text:mode==='limited'?JSON.stringify({code:1309,msg:'subject_ip_rate_limit'}):''};
}};
const { PosterMetadataService: Service } = await loadEts('data/PosterMetadataService.ets', [
  ["import { HttpClient } from '../net/HttpClient';",'const HttpClient = globalThis.__posterHttp;'],
  ["import { Store } from './Store';",'const Store = globalThis.__posterStore;'],
  ["import { PosterCardData, PosterCardInfo, PosterStaticInfo } from '../model/PosterCardData';",'const PosterCardData = globalThis.__posterData;']
]);
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const nextHeld=async()=>{for(let i=0;i<400&&held.length===0;i++)await new Promise(r=>setTimeout(r,5));return held.shift();};
const response=(id,comments=12000,rating=7.2)=>({ok:true,status:200,text:JSON.stringify({id,is_tv:false,comment_count:comments,rating:{value:rating},durations:['120分钟'],countries:['美国']})});

test('requests deduplicate and cap concurrency, persist static fields, and always refresh scores and heat', async () => {
  const ids=['10000001','10000002','10000003','10000004','10000005'];
  const requests=ids.map(id=>Service.request(id,false));
  assert.equal(Service.request(ids[0],false),requests[0]);
  assert.ok(calls.length<=2);
  for(let i=0;i<ids.length;i++) {
    const job=await nextHeld();assert.ok(job);job.resolve(response(job.url.split('/').at(-1)));await tick();
  }
  const info=await Promise.all(requests);
  assert.ok(maxActive<=2);assert.equal(calls.length,5);
  assert.ok(info.every(x=>x.shortComments===12000));
  assert.equal(storage.has('poster_meta_index_v1'),false);
  assert.equal(storage.has('poster_meta_v1_10000000'),false);
  assert.deepEqual(Service.peek('10000000').countries,['韩国']);
  assert.equal(Service.peek('10000000').rating,'');
  assert.equal(Service.peek('10000000').shortComments,-1);
  const cached=Service.peek(ids[0]);
  assert.deepEqual(cached.countries,['美国']);
  assert.equal(cached.shortComments,-1);assert.equal(cached.rating,'');
  const persisted=JSON.parse(storage.get('poster_static_v2_'+ids[0]));
  assert.equal('shortComments' in persisted.info,false);assert.equal('rating' in persisted.info,false);
  const count=calls.length;
  const refresh=Service.request(ids[0],false);
  const refreshJob=await nextHeld();
  assert.equal(calls.length,count+1);
  refreshJob.resolve(response(ids[0],50001,7.3));
  const current=await refresh;
  assert.equal(current.shortComments,50001);assert.equal(current.rating,'7.3');
  assert.equal(Service.peek(ids[0]).shortComments,-1);
  assert.ok([...storage.values()].every(value=>value.length<8000));
});
test('a fresh process restores only stable catalogue fields from disk', async () => {
  const { PosterMetadataService: ColdService } = await loadEts('data/PosterMetadataService.ets', [
    ["import { HttpClient } from '../net/HttpClient';",'const HttpClient = globalThis.__posterHttp; // cold process'],
    ["import { Store } from './Store';",'const Store = globalThis.__posterStore;'],
    ["import { PosterCardData, PosterCardInfo, PosterStaticInfo } from '../model/PosterCardData';",'const PosterCardData = globalThis.__posterData;']
  ]);
  const cached=ColdService.peek('10000001');
  assert.equal(cached.durationMinutes,120);assert.deepEqual(cached.countries,['美国']);
  assert.equal(cached.rating,'');assert.equal(cached.shortComments,-1);
});
test('missing IDs do not issue requests, failed details retry with the other type once and then back off', async () => {
  mode='missing';const before=calls.length;
  assert.equal(await Service.request('431299',false),null);
  assert.equal(calls.length,before);
  assert.equal(await Service.request('10000006',false),null);
  assert.equal(calls.length,before+3);
  assert.equal(await Service.request('10000006',false),null);
  assert.equal(calls.length,before+3);
});
test('rate limiting stops queued network requests without overwriting stale usable fields', async () => {
  mode='limited';const previousNow=Date.now;const time=previousNow()+13*60*60*1000;
  Date.now=()=>time;
  try {
    const before=calls.length;
    const requests=['10000001','10000007','10000008','10000009'].map(id=>Service.request(id,false));
    const results=await Promise.all(requests);
    assert.equal(results[0].liveMetadata,false);
    assert.equal(Service.peek('10000001').durationMinutes,120);
    assert.equal(Service.peek('10000001').rating,'');
    assert.equal(Service.peek('10000001').shortComments,-1);
    assert.ok(results.every(x=>x!==null && x.shortComments===-1 && x.rating===''));
    assert.ok(calls.slice(before).filter(url=>url.includes('/rexxar/')).length<=2);
    assert.ok(!calls.slice(before).some(url=>url.includes('/tv/')));
  } finally {Date.now=previousNow;}
});
