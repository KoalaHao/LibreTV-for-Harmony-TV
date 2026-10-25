import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
let native;
globalThis.__loudnessMedia={createAVPlayer:async()=>native,createMediaSourceWithUrl:(url,headers)=>({url,headers})};
const {AvPlayerController:Player}=await loadEts('player/AvPlayerController.ets',[
 ["import { media } from '@kit.MediaKit';",'const media=globalThis.__loudnessMedia;'],
 ["import { audio } from '@kit.AudioKit';",'const audio={StreamUsage:{STREAM_USAGE_MOVIE:3}};'],
 ["import { BusinessError } from '@kit.BasicServicesKit';",'']
]);
const flush=()=>new Promise(resolve=>setImmediate(resolve));
async function setup(){
 const calls=[];native={state:'idle',duration:100000,listeners:new Map(),on(e,cb){this.listeners.set(e,cb);},
  setMediaSource(){this.state='initialized';},prepare(){},setVolume(){},setLoudnessGain:async v=>{calls.push(['gain',v]);},
  play(){calls.push(['play']);this.state='playing';},reset(){this.state='idle';},stop(){},release(){}};
 const c=new Player();await c.create('surface');return {c,p:native,calls};
}
test('saved compensation is applied to the movie renderer before autoplay, and an unrelated source resets to zero',async()=>{
 const {c,p,calls}=await setup();c.configureLoudnessGain(6);
 await c.playUrl('https://media.test/1.m3u8',{});assert.equal(p.audioRendererInfo.usage,3);
 p.state='prepared';p.listeners.get('stateChange')('prepared');await flush();
 assert.deepEqual(calls.slice(0,2),[['gain',6],['play']]);
 c.configureLoudnessGain(0);await c.playUrl('https://media.test/other.m3u8',{});
 p.state='prepared';p.listeners.get('stateChange')('prepared');await flush();
 assert.deepEqual(calls.slice(-2),[['gain',0],['play']]);
});
test('dynamic gain changes preserve pause, seek and system volume and report unsupported routes without fatal media errors',async()=>{
 const {c,p,calls}=await setup();const errors=[];c.onError=e=>errors.push(e);p.state='paused';
 assert.equal(await c.setLoudnessGain(12),true);assert.equal(p.state,'paused');assert.deepEqual(calls,[['gain',12]]);
 p.setLoudnessGain=async()=>{p.listeners.get('error')({code:5400108});};
 assert.equal(await c.setLoudnessGain(6),false);assert.deepEqual(errors,[]);assert.equal(p.state,'paused');
 p.setLoudnessGain=async()=>{throw Error('unsupported');};assert.equal(await c.setLoudnessGain(6),false);
});
test('a late gain result for a previous video cannot publish into the newly configured source',async()=>{
 const {c,p}=await setup();let finish;const states=[];p.state='playing';c.onLoudnessState=(s,v)=>states.push([s,v]);
 p.setLoudnessGain=()=>new Promise(resolve=>finish=resolve);
 const old=c.setLoudnessGain(6);await flush();c.configureLoudnessGain(0);finish();
 assert.equal(await old,false);assert.deepEqual(states,[['applying',6]]);
 c.release();assert.equal(await c.setLoudnessGain(12),false);
});
