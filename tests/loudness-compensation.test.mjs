import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
let native;
globalThis.__loudnessAudio={StreamUsage:{STREAM_USAGE_MOVIE:3}};
globalThis.__loudnessMedia={createAVPlayer:async()=>native,createMediaSourceWithUrl:(url,headers)=>({url,headers})};
const {AvPlayerController:Player}=await loadEts('player/AvPlayerController.ets',[
 ["import { media } from '@kit.MediaKit';",'const media=globalThis.__loudnessMedia;'],
 ["import { audio } from '@kit.AudioKit';",'const audio=globalThis.__loudnessAudio;'],
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
test('an unfulfilled native Promise cannot block autoplay and reports requested rather than failed or verified',async()=>{
 const {c,p,calls}=await setup();const states=[];c.onLoudnessState=(s,v)=>states.push([s,v]);
 p.setLoudnessGain=v=>{calls.push(['gain',v]);return new Promise(()=>{});};
 await c.playUrl('https://media.test/hung-gain.m3u8',{});p.state='prepared';p.listeners.get('stateChange')('prepared');
 await flush();assert.deepEqual(calls,[['gain',0],['play']]);assert.equal(p.state,'playing');
 await new Promise(resolve=>setTimeout(resolve,1100));assert.deepEqual(states.at(-1),['requested',0]);
 p.setLoudnessGain=async v=>calls.push(['gain',v]);assert.equal(await c.setLoudnessGain(6),true);c.release();
});
test('a native implementation with unfulfilled Promises still allows six, twelve and off while paused',async()=>{
 const {c,p,calls}=await setup();const states=[];p.state='paused';c.onLoudnessState=(s,v)=>states.push([s,v]);
 p.setLoudnessGain=v=>{calls.push(['gain',v]);return new Promise(()=>{});};
 for(const gain of [6,12,0])assert.equal(await c.setLoudnessGain(gain),true);
 assert.deepEqual(calls,[['gain',6],['gain',12],['gain',0]]);assert.equal(p.state,'paused');
 assert.deepEqual(states.filter(([s])=>s==='requested'),[['requested',6],['requested',12],['requested',0]]);
 assert.equal(states.some(([s])=>s==='applied'||s==='unavailable'),false);c.release();
});
test('a late rejection after the compatibility wait rolls back the accepted preference',async()=>{
 const {c,p}=await setup();let reject;const states=[];p.state='playing';c.onLoudnessState=(s,v)=>states.push([s,v]);
 p.setLoudnessGain=()=>new Promise((_,fail)=>reject=fail);
 assert.equal(await c.setLoudnessGain(6),true);assert.deepEqual(states.at(-1),['requested',6]);
 reject(Error('unsupported'));await flush();assert.deepEqual(states.at(-1),['unavailable',0]);
 p.setLoudnessGain=async()=>{};assert.equal(await c.setLoudnessGain(12),true);c.release();
});
test('late native gain errors roll back without stopping video and unrelated media failures are not swallowed',async()=>{
 const {c,p}=await setup();const errors=[],states=[];p.state='playing';c.onError=e=>errors.push(e);c.onLoudnessState=(s,v)=>states.push([s,v]);
 p.setLoudnessGain=()=>new Promise(()=>{});assert.equal(await c.setLoudnessGain(6),true);
 p.listeners.get('error')({code:5400102,message:'unsupport stream type'});
 assert.deepEqual(states.at(-1),['unavailable',0]);assert.deepEqual(errors,[]);assert.equal(p.state,'playing');
 p.setLoudnessGain=async()=>{p.listeners.get('error')({code:5400105,message:'Service died'});};
 await c.setLoudnessGain(12);assert.equal(errors.length,1);c.release();
});
test('a previous source rejection cannot roll back a newly configured source',async()=>{
 const {c,p}=await setup();let reject;const states=[];p.state='playing';c.onLoudnessState=(s,v)=>states.push([s,v]);
 p.setLoudnessGain=()=>new Promise((_,fail)=>reject=fail);
 const old=c.setLoudnessGain(6);await flush();c.configureLoudnessGain(0);reject(Error('old source'));
 assert.equal(await old,false);assert.deepEqual(states,[['applying',6]]);
 p.setLoudnessGain=async()=>{};assert.equal(await c.setLoudnessGain(12),true);assert.deepEqual(states.at(-1),['applied',12]);c.release();
});
test('the maximum 24 dB setting reaches the movie renderer, while a saved out-of-range 36 dB never reaches native',async()=>{
 const {c,p,calls}=await setup();c.configureLoudnessGain(24);
 await c.playUrl('https://media.test/max-gain.m3u8',{});p.state='prepared';p.listeners.get('stateChange')('prepared');await flush();
 assert.deepEqual(calls.slice(0,2),[['gain',24],['play']]);
 c.configureLoudnessGain(36);await c.playUrl('https://media.test/invalid-saved-gain.m3u8',{});
 p.state='prepared';p.listeners.get('stateChange')('prepared');await flush();
 assert.deepEqual(calls.slice(-2),[['gain',0],['play']]);assert.equal(calls.some(([name,value])=>name==='gain'&&value===36),false);c.release();
});
test('an audio renderer rebuilt at an ad boundary receives the current gain without restarting or seeking video',async()=>{
 let callback;const removals=[];
 const info=id=>({streamId:id,rendererInfo:{usage:3},deviceDescriptors:[]});
 globalThis.__loudnessAudio.getAudioManager=()=>({getStreamManager:()=>({
  getCurrentAudioRendererInfoArraySync:()=>[info(100)],on(type,cb){callback=cb;},off(type,cb){removals.push([type,cb]);}
 })});
 const {c,p,calls}=await setup();p.state='playing';assert.equal(await c.setLoudnessGain(24),true);
 callback([info(200)]);await new Promise(resolve=>setTimeout(resolve,300));
 assert.deepEqual(calls,[['gain',24],['gain',24]]);assert.equal(p.state,'playing');
 callback([info(200)]);await new Promise(resolve=>setTimeout(resolve,300));assert.equal(calls.length,2);
 c.configureLoudnessGain(0);callback([info(300)]);await new Promise(resolve=>setTimeout(resolve,300));assert.equal(calls.length,2);
 c.release();assert.deepEqual(removals,[['audioRendererChange',callback]]);delete globalThis.__loudnessAudio.getAudioManager;
});
test('unrelated renderers, a source switch and release cannot restore an old source gain',async()=>{
 let callback;const info=(id,usage=3)=>({streamId:id,rendererInfo:{usage},deviceDescriptors:[]});
 globalThis.__loudnessAudio.getAudioManager=()=>({getStreamManager:()=>({
  getCurrentAudioRendererInfoArraySync:()=>[info(1)],on(type,cb){callback=cb;},off(){}
 })});
 const {c,p,calls}=await setup();p.state='playing';await c.setLoudnessGain(12);
 callback([info(1),info(2,4)]);await new Promise(resolve=>setTimeout(resolve,300));assert.deepEqual(calls,[['gain',12]]);
 callback([info(3)]);c.configureLoudnessGain(0);await new Promise(resolve=>setTimeout(resolve,300));assert.equal(calls.length,1);
 c.configureLoudnessGain(24);callback([info(4)]);c.release();await new Promise(resolve=>setTimeout(resolve,300));assert.equal(calls.length,1);
 delete globalThis.__loudnessAudio.getAudioManager;
});
test('format metadata changes restore gain even if the renderer ID is reused, while a manual off cancels restoration',async()=>{
 const {c,p,calls}=await setup();p.state='paused';await c.setLoudnessGain(12);
 p.listeners.get('trackInfoUpdate')([]);await new Promise(resolve=>setTimeout(resolve,300));
 assert.deepEqual(calls,[['gain',12],['gain',12]]);assert.equal(p.state,'paused');
 p.listeners.get('videoSizeChange')(1920,1080);p.listeners.get('videoSizeChange')(1280,720);
 await new Promise(resolve=>setTimeout(resolve,300));assert.deepEqual(calls.at(-1),['gain',12]);assert.equal(calls.length,3);
 p.listeners.get('trackInfoUpdate')([]);await c.setLoudnessGain(0);
 await new Promise(resolve=>setTimeout(resolve,300));assert.deepEqual(calls.at(-1),['gain',0]);assert.equal(calls.length,4);c.release();
});
