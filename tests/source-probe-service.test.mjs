import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');globalThis.__specUtils=Utils;
const disk=new Map(),held=[],calls=[];
let sourceUrl='https://source.test';
globalThis.__specStorage={read:key=>disk.get(key)||'',write:(key,text)=>disk.set(key,text)};
globalThis.__specSources={shared:()=>({getVodSource:key=>({key,name:key,url:sourceUrl,enabled:true,isAdult:false,failStreak:0,disabledUntil:0})})};
globalThis.__specProbe={run:async(item,source,wanted)=>{calls.push(item.vodId);return new Promise(resolve=>held.push({item,wanted,resolve}));}};
const {SourceProbeService:Service}=await loadEts('data/SourceProbeService.ets',[
 ["import { SearchItem, VodSource } from '../model/Types';",''],
 ["import { SourceProbe, SourceProbeResult } from '../model/SourceProbe';",'const SourceProbe=globalThis.__specProbe;'],
 ["import { SourceManager } from './SourceManager';",'const SourceManager=globalThis.__specSources;'],
 ["import { SearchCacheStorage } from './SearchCacheStorage';",'const SearchCacheStorage=globalThis.__specStorage;'],
 ["import { Utils } from '../common/Utils';",'const Utils=globalThis.__specUtils;']
]);
const item=id=>({sourceKey:'a',sourceName:'A',vodId:id,name:'影片'});
const result=(id,w=1920,h=1080,status='ok')=>({sourceKey:'a',vodId:id,checkedAt:Date.now(),status,latencyMs:120,width:w,height:h,resolutionAt:w>0?Date.now():0,resolutionSource:w>0?'stream':'none',httpStatus:200,note:''});
const tick=()=>new Promise(r=>setImmediate(r));
test('resource probes deduplicate, cap concurrency at two, persist measurements and reuse one-day cache',async()=>{
 const promises=['1','2','3'].map(id=>Service.request(item(id),'page'));
 assert.equal(Service.request(item('1'),'page2'),promises[0]);assert.equal(calls.length,2);
 for(let n=0;n<3;n++){const job=held.shift();job.resolve(result(job.item.vodId));await tick();}
 await Promise.all(promises);const before=calls.length;assert.equal((await Service.request(item('1'),'page')).width,1920);assert.equal(calls.length,before);
 assert.equal(Service.peek(item('1')).latencyMs,120);assert.ok(disk.size>=3);
});
test('forced refresh keeps last known dimensions when current connectivity or parsing cannot supply them',async()=>{
 const old=Service.peek(item('1'));const request=Service.request(item('1'),'page',true);
 held.shift().resolve({...result('1',0,0,'failed'),checkedAt:old.checkedAt+100,httpStatus:403});
 const current=await request;assert.equal(current.width,1920);assert.equal(current.resolutionAt,old.resolutionAt);assert.equal(current.status,'failed');
 assert.equal(Service.fresh({...current,checkedAt:Date.now()-6*60000}),false);
 assert.equal(Service.fresh({...old,checkedAt:Date.now()-25*3600000}),false);
});
test('leaving a page cancels unstarted work, while another visible subscriber can keep its probe',async()=>{
 const before=calls.length;
 const a=Service.request(item('10'),'old'),b=Service.request(item('11'),'old'),c=Service.request(item('12'),'old');
 const shared=Service.request(item('12'),'new');assert.equal(c,shared);
 const removed=Service.request(item('13'),'old');Service.cancel('old');assert.equal(await removed,null);
 for(let n=0;n<3;n++){const job=held.shift();assert.ok(job);job.resolve(job.wanted()?result(job.item.vodId):null);await tick();}
 await Promise.all([a,b,c]);assert.equal(calls.length,before+3);assert.ok(!calls.includes('13'));
});
test('changing a configured endpoint invalidates probe identity rather than reusing another endpoint measurement',()=>{
 assert.ok(Service.peek(item('2')));sourceUrl='https://changed.test';assert.equal(Service.peek(item('2')),null);sourceUrl='https://source.test';
});
