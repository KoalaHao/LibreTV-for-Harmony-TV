import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');globalThis.__resolverUtils=Utils;
const {AdDiagnostics:D}=await loadEts('model/AdDiagnostics.ets',[[/^import .*;$/gm,''],[/^/,'const Utils=globalThis.__resolverUtils;\n']]);
let calls=0,outcome;
globalThis.__resolverKit={AdDiagnostics:D,Utils,fs:{statSync:()=>({size:100})},HttpClient:{},
 M3u8Rewriter:{rewrite:async()=>{calls++;return outcome;}}};
const {PlayUrlResolver:R}=await loadEts('player/PlayUrlResolver.ets',[[/^import .*;$/gm,''],[/^/,'const {Utils,AdDiagnostics,fs,HttpClient,M3u8Rewriter}=globalThis.__resolverKit;\n']]);
test('filter Off and non-HLS playback do not fetch an extra manifest for diagnosis',async()=>{
 calls=0;const off=await R.resolve('https://v.test/x.m3u8?token=SECRET','off','/tmp');
 const mp4=await R.resolve('https://v.test/x.mp4','strict','/tmp');
 assert.equal(calls,0);assert.equal(off.trace.status,'off');assert.equal(mp4.trace.status,'direct');
 assert.equal(off.url,'https://v.test/x.m3u8?token=SECRET');assert.doesNotMatch(off.trace.playlistUrl,/SECRET/);
});
test('rewrite failure retains direct playback and cannot claim that planned removals were applied',async()=>{
 const trace=D.empty('loose','fallback','https://v.test/x.m3u8');trace.filteredCount=8;
 outcome={ok:false,file:null,error:'write failed',trace};
 const result=await R.resolve('https://v.test/x.m3u8','loose','/tmp');
 assert.equal(result.kind,'url');assert.equal(result.filteredCount,0);assert.equal(result.trace.status,'fallback');
 assert.match(D.view(result.trace,1000).summary,/没有应用/);
});
test('a local rewritten playback carries the same trace whose filtered timeline the player will use',async()=>{
 const trace=D.empty('strict','rewritten','https://v.test/media.m3u8');
 outcome={ok:true,file:{fd:42},localPath:'/tmp/index.m3u8',filteredCount:3,trace};
 const result=await R.resolve('https://v.test/x.m3u8','strict','/tmp');
 assert.equal(result.kind,'fd');assert.match(result.url,/fd:\/\/42/);assert.equal(result.trace,trace);assert.equal(result.filteredCount,3);
});
