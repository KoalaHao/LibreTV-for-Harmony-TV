import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');globalThis.__timelineUtils=Utils;
const {AdDiagnostics}=await loadEts('model/AdDiagnostics.ets',[[/^import .*;$/gm,''],[/^/,'const Utils=globalThis.__timelineUtils;\n']]);
globalThis.__timelineDiagnostics=AdDiagnostics;
const {AdFilterTimeline:T}=await loadEts('model/AdFilterTimeline.ets',[[/^import .*;$/gm,''],[/^/,'const AdDiagnostics=globalThis.__timelineDiagnostics;\n']]);
const trace=dropped=>({...AdDiagnostics.empty('strict','rewritten'),timelineUsable:true,originalCount:3,
 segments:[
  {sourceStartMs:0,startMs:0,endMs:10000,durationMs:10000,dropped:false},
  {sourceStartMs:10000,startMs:10000,endMs:dropped?10000:14000,durationMs:4000,dropped},
  {sourceStartMs:14000,startMs:dropped?10000:14000,endMs:dropped?20000:24000,durationMs:10000,dropped:false}
 ]});
test('changing filter keeps the same content anchor after removed ads and when restoring original media',()=>{
 assert.equal(T.toSource(trace(true),12000,20000),16000);
 assert.equal(T.fromSource(trace(false),16000),16000);
 assert.equal(T.fromSource(trace(true),16000),12000);
 assert.equal(T.toSource(trace(false),16000,24000),16000);
});
test('a position inside a newly removed ad resumes at the next kept content and end anchors are clamped',()=>{
 assert.equal(T.fromSource(trace(true),11000),10000);
 assert.equal(T.fromSource(trace(true),24000),20000);
});
test('unknown, live or inconsistent timelines retain the current numeric progress',()=>{
 assert.equal(T.toSource(trace(true),12000,80000),12000);
 assert.equal(T.fromSource(AdDiagnostics.empty('off','direct'),16000),16000);
 assert.equal(T.fromSource({...trace(true),live:true},16000),16000);
});
