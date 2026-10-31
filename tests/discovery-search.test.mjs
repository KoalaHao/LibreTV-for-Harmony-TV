import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { Utils } = await loadEts('common/Utils.ets');
globalThis.__discoveryUtils=Utils;
const storage=new Map(), calls=[], held=[];
let sources=[{key:'a',name:'A',url:'https://a.test',enabled:true,isAdult:false},{key:'b',name:'B',url:'https://b.test',enabled:true,isAdult:false}];
const settings={adultFilter:true};
const realNow=Date.now;let clockOffset=0;Date.now=()=>realNow()+clockOffset;
globalThis.__discoveryStorage={read:key=>storage.get(key)||'',write:(key,text)=>storage.set(key,text)};
globalThis.__discoverySources={shared:()=>({getVodSources:()=>sources,searchableVodSources:()=>sources.filter(x=>x.enabled)})};
globalThis.__discoverySearch={aggregate:async keyword=>{calls.push(keyword);return new Promise(resolve=>held.push({keyword,resolve}));}};
const { DiscoverySearchService: Service }=await loadEts('data/DiscoverySearchService.ets',[
 ["import { MergedVideo, SearchItem, Settings } from '../model/Types';",''],
 ["import { SearchService } from '../model/SearchService';",'const SearchService=globalThis.__discoverySearch;'],
 ["import { SourceManager } from './SourceManager';",'const SourceManager=globalThis.__discoverySources;'],
 ["import { SearchCacheStorage } from './SearchCacheStorage';",'const SearchCacheStorage=globalThis.__discoveryStorage;'],
 ["import { Utils } from '../common/Utils';",'const Utils=globalThis.__discoveryUtils;']
]);
globalThis.__discoveryService=Service;
const { DiscoverySearchSession: Session }=await loadEts('model/DiscoverySearchSession.ets',[
 ["import { MergedVideo, Settings, DEFAULT_SETTINGS } from './Types';",'const DEFAULT_SETTINGS={adultFilter:true};'],
 ["import { DiscoverySearchService } from '../data/DiscoverySearchService';",'const DiscoverySearchService=globalThis.__discoveryService;']
]);
const group=(name,id='1')=>({name,year:'2026',items:[{sourceKey:'a',sourceName:'A',vodId:id,name,remarks:'1080P',playUrl:'https://expiring.test/video',content:'not cached'}]});
const reply=(name,id='1')=>({merged:[group(name,id)],failedCount:0});
const tick=()=>new Promise(r=>setImmediate(r));

test('cache survives new sessions, has a one-day freshness window, and stores selection data without playback URLs',async()=>{
 assert.equal(Service.peek('电影',settings),null);
 const request=Service.refresh('电影',settings);
 assert.equal(Service.refresh('电影',settings),request);
 held.shift().resolve(reply('电影'));await request;
 const cached=Service.peek('电影',settings);assert.equal(cached.results[0].items[0].vodId,'1');assert.equal(Service.stale(cached),false);
 assert.equal(cached.results[0].items[0].remarks,'1080P');
 const persisted=[...storage.values()].join('');assert.ok(!persisted.includes('expiring.test'));assert.ok(!persisted.includes('not cached'));
 const count=calls.length;const session=new Session();session.open('电影',settings);assert.equal(calls.length,count);assert.equal(session.state.results.length,1);
 const now=Date.now;Date.now=()=>cached.updatedAt+25*3600000;
 try { assert.equal(Service.stale(Service.peek('电影',settings)),true); } finally {Date.now=now;}
});
test('stale results remain selectable while automatic refresh is unresolved, then swap after success',async()=>{
 clockOffset+=25*3600000;
 const session=new Session();
 try {
  session.open('电影',settings);assert.equal(session.state.refreshing,true);
  assert.equal(session.state.results[0].items[0].vodId,'1');assert.equal(Service.peek('电影',settings).results[0].items[0].vodId,'1');
  held.shift().resolve(reply('电影','2'));await tick();
  assert.equal(session.state.refreshing,false);assert.equal(session.state.results[0].items[0].vodId,'2');
 } finally {session.close();}
});
test('manual refresh bypasses a fresh cache without clearing or disabling the existing choices',async()=>{
 const session=new Session();session.open('电影',settings);const previous=session.state.results;
 const before=calls.length;const refreshing=session.refresh();assert.equal(calls.length,before+1);assert.equal(session.state.results,previous);
 held.shift().resolve(reply('电影','3'));await refreshing;
 assert.equal(session.state.results[0].items[0].vodId,'3');assert.equal(session.state.refreshing,false);
});
test('all-source failure retains the previous cache and original freshness timestamp',async()=>{
 const previous=Service.peek('电影',settings);const request=Service.refresh('电影',settings);
 held.shift().resolve({merged:[],failedCount:2});const result=await request;
 assert.equal(result.cache.updatedAt,previous.updatedAt);assert.equal(result.cache.results[0].items[0].vodId,'3');assert.notEqual(result.error,'');
 assert.equal(Service.peek('电影',settings).updatedAt,previous.updatedAt);
});
test('returning from a selected source rejoins its pending manual refresh without clearing cached choices',async()=>{
 const prime=Service.refresh('回返',settings);held.shift().resolve(reply('回返','old'));await prime;
 const session=new Session();session.open('回返',settings);const before=calls.length;
 const updating=session.refresh();session.close();session.open('回返',settings);
 assert.equal(calls.length,before+1);assert.equal(session.state.refreshing,true);
 assert.equal(session.state.results[0].items[0].vodId,'old');
 held.shift().resolve(reply('回返','new'));await updating;await tick();
 assert.equal(session.state.refreshing,false);assert.equal(session.state.results[0].items[0].vodId,'new');
});
test('cache identity changes with configured sources and adult filtering',()=>{
 assert.ok(Service.peek('电影',settings));const before=sources;
 sources=[{...before[0],url:'https://changed.test'},before[1]];
 assert.equal(Service.peek('电影',settings),null);sources=before;
 assert.equal(Service.peek('电影',{adultFilter:false}),null);assert.ok(Service.peek('电影',settings));
});
test('a different title or dismissed page ignores late completions, while the service still caches them',async()=>{
 const session=new Session();session.open('甲',settings);session.open('乙',settings);
 const a=held.shift(),b=held.shift();a.resolve(reply('甲'));await tick();assert.equal(session.state.results.length,0);
 b.resolve(reply('乙'));await tick();assert.equal(session.state.results[0].name,'乙');
 session.open('丙',settings);const c=held.shift();session.close();c.resolve(reply('丙'));await tick();
 assert.equal(session.state.results.length,0);assert.equal(Service.peek('丙',settings).results[0].name,'丙');
});
test('successful empty results are cached, while invalid disk data is ignored',async()=>{
 const request=Service.refresh('空',settings);held.shift().resolve({merged:[],failedCount:0});await request;
 assert.deepEqual(Service.peek('空',settings).results,[]);
 const key=[...storage.keys()].find(k=>JSON.parse(storage.get(k)).keyword==='空');
 const saved=storage.get(key);storage.set(key,'<html>not JSON</html>');assert.equal(Service.peek('空',settings),null);
 storage.set(key,saved.replace('"keyword":"空"','"keyword":"别的影片"'));assert.equal(Service.peek('空',settings),null);
});
test('fresh search results are immediately selectable on entry without repeating the aggregate request',()=>{
 const session=new Session(),before=calls.length,seed={results:[group('搜索直达','seed')],updatedAt:Date.now()};
 session.open('搜索直达',settings,seed);assert.equal(calls.length,before);assert.equal(session.state.fromSeed,true);
 assert.equal(session.state.results[0].items[0].vodId,'seed');assert.equal(session.state.refreshing,false);session.close();
});
test('a newer search seed takes precedence over an older title cache and a manual refresh can replace it',async()=>{
 const request=Service.refresh('较新搜索',settings);held.shift().resolve(reply('较新搜索','old'));await request;
 clockOffset+=1000;
 const session=new Session(),before=calls.length;
 session.open('较新搜索',settings,{results:[group('较新搜索','fresh')],updatedAt:Date.now()});
 assert.equal(calls.length,before);assert.equal(session.state.results[0].items[0].vodId,'fresh');
 const refreshing=session.refresh();assert.equal(session.state.results[0].items[0].vodId,'fresh');
 held.shift().resolve(reply('较新搜索','refreshed'));await refreshing;
 assert.equal(session.state.results[0].items[0].vodId,'refreshed');assert.equal(session.state.fromSeed,false);session.close();
});
test('an expired search seed refreshes in the background and remains visible if the request fails',async()=>{
 const session=new Session();session.open('旧的搜索入口',settings,{results:[group('旧的搜索入口','seed')],updatedAt:Date.now()-25*3600000});
 assert.equal(session.state.refreshing,true);assert.equal(session.state.results[0].items[0].vodId,'seed');
 held.shift().resolve({merged:[],failedCount:2});await tick();
 assert.equal(session.state.results[0].items[0].vodId,'seed');assert.notEqual(session.state.error,'');session.close();
});
test('completed explicit searches persist the full query without refetching or retaining expiring media data',()=>{
 const before=calls.length,now=Date.now();Service.remember('同名',settings,[group('同名电影','a'),{...group('同名剧集','b'),year:'2020'}],now);
 const cached=Service.peek('同名',settings);assert.equal(calls.length,before);assert.equal(cached.results.length,2);
 assert.equal(cached.updatedAt,now);assert.equal(cached.results[0].items[0].playUrl,undefined);
 assert.equal(cached.results[0].items[0].content,undefined);
 const session=new Session();session.open('同名',settings,{results:[group('同名电影','a')],updatedAt:now});
 assert.equal(calls.length,before);assert.equal(session.state.fromSeed,false);assert.equal(session.state.results.length,2);session.close();
});
