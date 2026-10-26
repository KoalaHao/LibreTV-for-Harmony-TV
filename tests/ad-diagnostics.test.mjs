import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');globalThis.__adUtils=Utils;
const ad=await loadEts('model/AdDiagnostics.ets',[[/^import .*;$/gm,''],[/^/,'const Utils=globalThis.__adUtils;\n']]);
globalThis.__adModels=ad;
let response={ok:true,text:'',error:''},failWrite=false;
globalThis.__adPlatform={
 HttpClient:{getTextResilient:async()=>response},
 fs:{accessSync(){return false;},mkdirSync(){},openSync(){return {fd:1};},writeSync(){if(failWrite)throw Error('disk full');},closeSync(){},OpenMode:{READ_WRITE:1,CREATE:2,TRUNC:4}},
 util:{TextEncoder:{create:()=>({encodeInto:text=>new TextEncoder().encode(text)})}}
};
const {M3u8Rewriter:R}=await loadEts('model/M3u8Rewriter.ets',[[/^import .*;$/gm,''],[/^/,`const Utils=globalThis.__adUtils;const {AdDiagnostics}=globalThis.__adModels;const {HttpClient,fs,util}=globalThis.__adPlatform;\n`]]);
const {AdDiagnostics:D,AdDiagnosticSession:Session}=ad;
const base='https://main.test/f/playlist.m3u8?auth=SECRET';
const playlist=segments=>['#EXTM3U','#EXT-X-TARGETDURATION:8',...segments.flatMap(s=>[...(s.disc?['#EXT-X-DISCONTINUITY']:[]),`#EXTINF:${s.dur},`,s.uri]),'#EXT-X-ENDLIST'].join('\n');
const original=[{dur:6,uri:'https://main.test/1.ts?token=SECRET'},
 {dur:6,uri:'https://main.test/2.ts'},{dur:6,uri:'https://main.test/3.ts'},
 {dur:2,uri:'https://ad.test/ads/a.ts',disc:true},{dur:2,uri:'https://ad.test/ads/b.ts'},
 {dur:6,uri:'https://main.test/4.ts',disc:true},{dur:6,uri:'https://main.test/5.ts'}];
const rewrite=(segments=original,mode='loose')=>R.rewriteMediaPlaylist(playlist(segments),base,mode);
test('removal decisions preserve the original sequence and map playback time on the filtered timeline',()=>{
 const result=rewrite();assert.equal(result.filteredCount,2);assert.equal(result.segmentCount,5);
 assert.equal(result.trace.originalCount,7);assert.equal(result.trace.filteredMs,4000);
 assert.equal(D.locate(result.trace,17999),2);assert.equal(D.locate(result.trace,18000),5);
 assert.equal(result.trace.segments[5].sourceStartMs,22000);assert.equal(result.trace.segments[5].startMs,18000);
 const view=D.view(result.trace,19000);assert.match(view.current,/#6/);assert.match(view.current,/估算/);
 assert.match(view.changes,/分组切换/);assert.match(view.changes,/中间有已过滤分片/);
 assert.ok(result.trace.segments[3].reason.includes('广告路径'));assert.match(result.trace.segments[5].reason,/未命中/);
 assert.equal(D.locate(result.trace,30000),-1);assert.equal(D.locate(result.trace,-1),-1);
});
test('strict, loose ungrouped, and all-removed protection retain the actual rule explanation',()=>{
 const items=[{dur:.5,uri:'a.ts'},{dur:2,uri:'b.ts'},{dur:6,uri:'c.ts'}];
 const loose=rewrite(items);assert.deepEqual(loose.trace.segments.map(s=>s.dropped),[true,false,false]);
 const strict=rewrite(items,'strict');assert.deepEqual(strict.trace.segments.map(s=>s.dropped),[true,true,false]);
 assert.match(strict.trace.segments[1].reason,/不足 3 秒/);
 const protectedList=rewrite([{dur:.5,uri:'a.ts'},{dur:.5,uri:'b.ts'}],'strict');
 assert.equal(protectedList.filteredCount,0);assert.ok(protectedList.trace.segments.every(s=>!s.dropped&&s.reason.includes('保护回退')));
});
test('domain changes remain observations, not proof of advertising',()=>{
 const result=rewrite([{dur:6,uri:'https://a.test/1.ts'},{dur:6,uri:'https://b.test/2.ts'}]);
 assert.equal(result.filteredCount,0);assert.match(D.view(result.trace,7000).changes,/域名变化/);
 assert.doesNotMatch(D.view(result.trace,7000).reason,/确定.*广告/);
});
test('live playlists, unknown durations and positions beyond the manifest never claim a current segment',()=>{
 const live=R.rewriteMediaPlaylist(playlist(original).replace('#EXT-X-ENDLIST',''),base,'loose').trace;
 assert.equal(D.locate(live,1000),-1);assert.match(D.view(live,1000).note,/动态清单/);
 const unknown=R.rewriteMediaPlaylist('#EXTM3U\na.ts\n#EXT-X-ENDLIST',base,'off').trace;
 assert.equal(D.locate(unknown,0),-1);assert.equal(unknown.timelineUsable,false);
 assert.equal(D.locate(rewrite().trace,Infinity),-1);
});
test('network or local-file failure says direct fallback and cannot map the planned filtered timeline',async()=>{
 response={ok:false,text:'',error:'HTTP 403'};
 let out=await R.rewrite(base,{},'loose','/tmp/test');assert.equal(out.ok,false);
 assert.match(D.view(out.trace,0).state,/回退直链/);assert.match(D.view(out.trace,0).summary,/没有应用/);
 response={ok:true,text:playlist(original),error:''};failWrite=true;
 out=await R.rewrite(base,{},'loose','/tmp/test');failWrite=false;
 assert.equal(out.ok,false);assert.equal(out.trace.filteredCount,2);assert.equal(D.locate(out.trace,19000),-1);
 assert.match(D.view(out.trace,19000).summary,/没有应用/);
});
test('mark captures the clip, progress, nearby decisions and a safe manifest snapshot without mutating playback',()=>{
 const trace=rewrite().trace,copy=JSON.stringify(trace);
 const context={sourceKey:'a',vodId:'42',title:'影片',episode:2,episodeName:'第三集',lineIndex:1};
 const report=D.report(trace,19001,context);assert.equal(report.estimatedSegment,6);assert.equal(report.positionMs,19001);
 assert.deepEqual(report.context,context);assert.ok(report.nearby.some(s=>s.dropped));assert.match(report.playlistSnapshot,/#EXTINF/);
 assert.doesNotMatch(JSON.stringify(report),/SECRET|token=|auth=/);assert.equal(JSON.stringify(trace),copy);
 assert.equal(D.safeUrl('https://user:secret@host.test/x.ts?token=SECRET#fragment'),'https://host.test/x.ts');
});
test('large snapshots are explicitly truncated, and a stale resolver cannot overwrite another source',()=>{
 const many=Array.from({length:1000},(_,i)=>({dur:6,uri:`https://main.test/${i}.ts`}));
 const trace=rewrite(many,'off').trace;const context={sourceKey:'b',vodId:'1',title:'B',episode:0,episodeName:'',lineIndex:0};
 const report=D.report(trace,3000000,context);assert.equal(report.snapshotTruncated,true);assert.ok(report.playlistSnapshot.length<132000);
 const session=new Session(),old=session.begin('loose');const now=session.begin('strict');
 assert.equal(session.update(old,trace),false);assert.equal(session.update(now,rewrite().trace),true);
 session.close();assert.equal(session.update(now,trace),false);assert.equal(session.current().segments.length,0);
});
test('a significant player/manifest duration mismatch suppresses misleading segment estimates',()=>{
 const trace=rewrite().trace;
 assert.equal(D.locate(trace,19000,34000),-1);assert.match(D.view(trace,19000,34000).note,/明显不一致/);
 assert.equal(D.locate(trace,19000,30500),5);
 const context={sourceKey:'a',vodId:'42',title:'影片',episode:0,episodeName:'',lineIndex:0};
 const report=D.report(trace,19000,context,34000);assert.equal(report.estimatedSegment,-1);assert.equal(report.playerDurationMs,34000);
});
test('reopening an existing play directory does not invoke mkdir and still writes a filtered playlist',async()=>{
 const kit=globalThis.__adPlatform,oldAccess=kit.fs.accessSync,oldMkdir=kit.fs.mkdirSync;
 let mkdirCalls=0;kit.fs.accessSync=()=>true;kit.fs.mkdirSync=()=>{mkdirCalls++;throw {code:13900015};};
 response={ok:true,text:playlist(original),error:''};
 try{const result=await R.rewrite(base,{},'loose','/existing/play');assert.equal(result.ok,true);assert.equal(result.filteredCount,2);assert.equal(mkdirCalls,0);}
 finally{kit.fs.accessSync=oldAccess;kit.fs.mkdirSync=oldMkdir;}
});
