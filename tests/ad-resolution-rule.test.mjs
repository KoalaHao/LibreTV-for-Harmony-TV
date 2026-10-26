import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
import {filmSps,adSps,baselineSps,tsPrefix} from './helpers/h264-headers.mjs';
const {Utils}=await loadEts('common/Utils.ets');
const {TsVideoDimensions}=await loadEts('model/TsVideoDimensions.ets');
globalThis.__resolutionKits={Utils,TsVideoDimensions};
let calls=[],running=0,peak=0,scenario;
const http={getVideoPrefix:async(url,headers,timeout)=>{
 calls.push({url,headers,timeout});running++;peak=Math.max(peak,running);
 try{
  await new Promise(resolve=>setImmediate(resolve));
  const index=Number(url.match(/\/(\d+)\.ts/)[1]);
  if(scenario.onProbe)scenario.onProbe(index);
  if(scenario.fail?.has(index))throw Error('unreachable');
  if(scenario.unknown?.has(index))return {ok:true,bytes:new Uint8Array(564)};
  const sps=scenario.dimensions?.get(index)??(index>=scenario.start&&index<scenario.end?scenario.ad:scenario.film);
  return {ok:true,bytes:tsPrefix(sps)};
 }finally{running--;}
}};
globalThis.__resolutionKits.HttpClient=http;
const {AdResolutionRule:R}=await loadEts('model/AdResolutionRule.ets',[[/^import .*;$/gm,''],[/^/,'const {Utils,TsVideoDimensions,HttpClient}=globalThis.__resolutionKits;\n']]);
const {AdDiagnostics}=await loadEts('model/AdDiagnostics.ets',[[/^import .*;$/gm,''],[/^/,'const {Utils}=globalThis.__resolutionKits;\n']]);
globalThis.__resolutionRewriter={Utils,AdDiagnostics,AdResolutionRule:R};
const {M3u8Rewriter:M}=await loadEts('model/M3u8Rewriter.ets',[[/^import .*;$/gm,''],[/^/,'const {Utils,AdDiagnostics,AdResolutionRule}=globalThis.__resolutionRewriter;\n']]);
let serial=0;
function setup(options={}){
 calls=[];peak=0;scenario={count:60,start:18,end:23,film:filmSps,ad:adSps,...options};
 const domain=`https://case-${++serial}.test/`;
 const durations=[4.867,3.333,6.367,2.100,2.967];
 const lines=['#EXTM3U','#EXT-X-TARGETDURATION:9',...(options.tags||[])];
 for(let i=0;i<scenario.count;i++){
  if(options.discs!==false&&(i%6===0||i===scenario.start||i===scenario.start+3||i===scenario.end))lines.push('#EXT-X-DISCONTINUITY');
  const dur=i>=scenario.start&&i<scenario.end?(durations[(i-scenario.start)%5]):4.171;
  lines.push(`#EXTINF:${dur},`,`${i}.ts?auth=fixture`);
 }
 lines.push('#EXT-X-ENDLIST');return {text:lines.join('\n'),base:domain+'index.m3u8'};
}
const inspect=(p,wanted)=>R.inspect(p.text,p.base,{'User-Agent':'fixture','Referer':p.base},wanted);
test('same-CDN insertion split across two discontinuity groups is removed only after all five samples and brackets agree',async()=>{
 const p=setup(),result=await M.analyzeMediaPlaylist(p.text,p.base,'strict',{});
 assert.deepEqual(result.trace.segments.filter(s=>s.reason.includes('异分辨率')).map(s=>s.index),[19,20,21,22,23]);
 assert.equal(result.filteredCount,5);assert.equal(result.trace.filteredMs,19634);
 for(const i of [16,17,23,24])assert.equal(result.trace.segments[i].dropped,false);
 assert.match(result.trace.segments[18].reason,/1918×802 → 1920×1080/);
 assert.match(AdDiagnostics.view(result.trace,0).note,/主样本 1918×802/);
 assert.ok(peak<=3);assert.ok(calls.every(c=>c.timeout<=2000));
});
test('off and loose retain exactly their original outputs and perform no new metadata requests',async()=>{
 const p=setup();for(const mode of ['off','loose']){
  const original=M.rewriteMediaPlaylist(p.text,p.base,mode);
  const now=await M.analyzeMediaPlaylist(p.text,p.base,mode,{});
  assert.equal(now.content,original.content);assert.equal(now.filteredCount,original.filteredCount);
 }assert.equal(calls.length,0);
});
test('irregular durations alone never trigger the new rule',async()=>{
 const p=setup({ad:filmSps}),result=await inspect(p);
 assert.deepEqual(result.matches,[]);assert.ok(calls.length>0);
 const now=await M.analyzeMediaPlaylist(p.text,p.base,'strict',{}),old=M.rewriteMediaPlaylist(p.text,p.base,'strict');
 assert.equal(now.content,old.content);assert.equal(now.filteredCount,2);
});
test('strict filtering also covers same-aspect insertions with a different encoded resolution',async()=>{
 const p=setup({film:baselineSps(1920,1080),ad:baselineSps(1280,720)});
 assert.deepEqual((await inspect(p)).matches.map(m=>[m.start,m.end]),[[18,23]]);
});
test('a long change, missing boundaries and an intro change are retained',async()=>{
 for(const options of [{start:18,end:38},{discs:false},{start:0,end:5}]){
  const p=setup(options);assert.deepEqual((await inspect(p)).matches,[],JSON.stringify(options));
 }
});
test('any unknown or failing sample inside an insertion prevents a partial resolution deletion',async()=>{
 for(const options of [{unknown:new Set([20])},{fail:new Set([20])},{unknown:new Set([17])},{unknown:new Set([24])}]){
  const p=setup(options);assert.deepEqual((await inspect(p)).matches,[]);
 }
});
test('live, encrypted, mapped, byte-range and non-TS playlists do not start this probe',async()=>{
 for(const change of [s=>s.replace('#EXT-X-ENDLIST',''),s=>s.replace('#EXTM3U','#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"'),
  s=>s.replace('#EXTM3U','#EXTM3U\n#EXT-X-MAP:URI="init.mp4"'),s=>s.replace('#EXTM3U','#EXTM3U\n#EXT-X-BYTERANGE:123'),
  s=>s.replaceAll('.ts','.m4s')]){
  const p=setup();p.text=change(p.text);assert.deepEqual((await inspect(p)).matches,[]);assert.equal(calls.length,0);
 }
});
test('fewer than seven matching distributed anchors cannot establish a main resolution',async()=>{
 const p=setup({dimensions:new Map([[3,adSps],[10,adSps],[30,adSps]])});
 const result=await inspect(p);assert.deepEqual(result.matches,[]);assert.match(result.note,/至少七个/);
 assert.equal(calls.length,9);
});
test('successful dimensions are reused for the same full URL and never reused for different signed URLs',async()=>{
 const p=setup();const first=await inspect(p);assert.equal(first.matches.length,1);const before=calls.length;
 assert.deepEqual((await inspect(p)).matches,first.matches);assert.equal(calls.length,before);
 p.text=p.text.replaceAll('auth=fixture','auth=changed');await inspect(p);assert.ok(calls.length>before);
});
test('request and wall-time budgets and source cancellation fail open without unbounded work',async()=>{
 let p=setup({count:2000,start:18,end:23});await inspect(p);assert.ok(calls.length<=160);assert.ok(peak<=3);
 let wanted=true;p=setup({onProbe:()=>{wanted=false;}});
 assert.deepEqual((await inspect(p,()=>wanted)).matches,[]);assert.ok(calls.length<=3);
 p=setup();const real=Date.now;let clock=0;
 try{Date.now=()=>clock+=2000;assert.deepEqual((await inspect(p)).matches,[]);assert.ok(calls.length<=3);}
 finally{Date.now=real;}
});
test('download segment selection uses the same bounded strict analysis as streaming playback',async()=>{
 const p=setup();http.getTextResilient=async()=>({ok:true,text:p.text});http.UA='fixture';
 globalThis.__resolutionDownload={Utils,AdDiagnostics,HttpClient:http,M3u8Rewriter:M};
 const {PlayUrlResolver:P}=await loadEts('player/PlayUrlResolver.ets',[[/^import .*;$/gm,''],[/^/,'const {Utils,AdDiagnostics,HttpClient,M3u8Rewriter}=globalThis.__resolutionDownload;\n']]);
 const result=await P.fetchSegments(p.base,'strict');assert.equal(result.error,'');assert.equal(result.urls.length,55);
 assert.ok(result.urls.every(url=>{const i=Number(url.match(/\/(\d+)\.ts/)[1]);return i<18||i>=23;}));
});
test('the decoder discontinuity is retained when the filtered playlist returns to the film',async()=>{
 const p=setup(),result=await M.analyzeMediaPlaylist(p.text,p.base,'strict',{});
 const output=result.content.split('\n'),resume=output.findIndex(line=>line.includes('/23.ts?'));
 const previous=output.slice(0,resume).findLastIndex(line=>line&&!line.startsWith('#'));
 assert.ok(output.slice(previous+1,resume).includes('#EXT-X-DISCONTINUITY'));
});
test('the same playlist keeps its first analysis when later metadata becomes available, preserving reprepare positions',async()=>{
 const p=setup({unknown:new Set([20])});const first=await inspect(p);assert.deepEqual(first.matches,[]);
 const before=calls.length;scenario.unknown.clear();assert.deepEqual((await inspect(p)).matches,[]);assert.equal(calls.length,before);
 p.text+='\n';assert.equal((await inspect(p)).matches.length,1);
});
