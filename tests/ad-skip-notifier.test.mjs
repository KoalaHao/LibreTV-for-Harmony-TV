import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {AdSkipNotifier:N}=await loadEts('model/AdSkipNotifier.ets',[[/^import .*;$/gm,'']]);
const trace=()=>({status:'rewritten',mode:'strict',live:false,timelineUsable:true,
 segments:[{startMs:0,endMs:10000,durationMs:10000,dropped:false},
  ...[5567,2933,5700,3333,1534].map(durationMs=>({startMs:10000,endMs:10000,durationMs,dropped:true})),
  {startMs:10000,endMs:20000,durationMs:10000,dropped:false}]});
test('crossing a removed interval emits its complete duration once while playback keeps progressing',()=>{
 const n=new N();n.configure(trace());n.anchor(9000);
 assert.equal(n.update(9999,true,20000),0);assert.equal(n.update(10020,true,20000),19067);
 assert.equal(n.update(10020,true,20000),0);assert.equal(n.update(11000,true,20000),0);
});
test('fresh entry, resume, explicit seek and a large position jump never report past cuts',()=>{
 const n=new N();n.configure(trace());assert.equal(n.update(12000,true,20000),0);
 n.anchor(9000);n.anchor(12000);assert.equal(n.update(12500,true,20000),0);
 n.anchor(4000);assert.equal(n.update(12000,true,20000),0);
 n.anchor(9000);assert.equal(n.update(10000,false,20000),0);assert.equal(n.update(10500,true,20000),0);
});
test('rewinding and playing through the same boundary again produces a new notice',()=>{
 const n=new N();n.configure(trace());n.anchor(9000);assert.equal(n.update(10500,true,20000),19067);
 assert.equal(n.update(9000,true,20000),0);assert.equal(n.update(10100,true,20000),19067);
});
test('off, live, failed, unknown and mismatched timelines cannot invent skip notifications',()=>{
 for(const patch of [{mode:'off'},{live:true},{status:'fallback'},{timelineUsable:false}]){
  const n=new N();n.configure({...trace(),...patch});n.anchor(9000);assert.equal(n.update(10100,true,20000),0);
 }
 const n=new N();n.configure(trace());n.anchor(9000);assert.equal(n.update(10100,true,60000),0);
 assert.equal(n.update(NaN,true,20000),0);assert.equal(n.update(10150,true,20000),0);
});
test('changing source clears old boundaries and repeated progress cannot show stale notices',()=>{
 const n=new N();n.configure(trace());n.anchor(9000);n.configure({...trace(),segments:[]});assert.equal(n.update(10100,true,0),0);
});
test('multiple cuts crossed in one normal progress update aggregate without queuing overlapping banners',()=>{
 const t=trace();t.segments.push({startMs:11000,endMs:11000,durationMs:5000,dropped:true},
  {startMs:11000,endMs:20000,durationMs:9000,dropped:false});
 const n=new N();n.configure(t);n.anchor(9000);assert.equal(n.update(11500,true,20000),24067);
});
