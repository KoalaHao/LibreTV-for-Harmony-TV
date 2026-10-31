import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
let factory;
globalThis.__realignMedia={createAVPlayer:()=>factory(),SeekMode:{SEEK_CLOSEST:2,SEEK_PREV_SYNC:0},
 createMediaSourceWithUrl:(url,headers)=>({url,headers})};
globalThis.__realignAudio={StreamUsage:{STREAM_USAGE_MOVIE:3}};
const {AvPlayerController:C}=await loadEts('player/AvPlayerController.ets',[
 ["import { media } from '@kit.MediaKit';",'const media=globalThis.__realignMedia;'],
 ["import { audio } from '@kit.AudioKit';",'const audio=globalThis.__realignAudio;'],
 ["import { BusinessError } from '@kit.BasicServicesKit';",'']]);
const flush=()=>new Promise(r=>setImmediate(r));
function player(name,calls){return {name,state:'idle',currentTime:0,duration:100000,listeners:new Map(),
 on(e,cb){this.listeners.set(e,cb);},setMediaSource(source,strategy){calls.push([name,'source',source,strategy]);this.state='initialized';},
 prepare(){calls.push([name,'prepare']);},setVolume(v){calls.push([name,'volume',v]);},
 async setLoudnessGain(v){calls.push([name,'gain',v]);},play(){calls.push([name,'play']);this.state='playing';},
 reset(){this.state='idle';},stop(){},release(){calls.push([name,'release']);this.state='released';},
 seek(ms,mode){calls.push([name,'seek',ms,mode]);this.currentTime=ms;}};}
async function prepared(p){p.state='prepared';p.listeners.get('stateChange')('prepared');await flush();}
test('manual realignment creates a fresh player, keeps the same source and precisely resumes with the saved gain',async()=>{
 const calls=[],old=player('old',calls),fresh=player('fresh',calls);factory=async()=>old;
 const c=new C();c.configureLoudnessGain(24);await c.create('surface');await c.playUrl('https://v.test/video.m3u8',{Referer:'fixture'});
 await prepared(old);old.currentTime=12345;const original=calls.find(x=>x[0]==='old'&&x[1]==='source')[2];factory=async()=>fresh;
 assert.equal(await c.realignPlayback(),true);assert.ok(calls.some(x=>x[0]==='old'&&x[1]==='release'));
 const issued=calls.find(x=>x[0]==='fresh'&&x[1]==='source');assert.equal(issued[2],original);
 await prepared(fresh);assert.ok(calls.some(x=>JSON.stringify(x)===JSON.stringify(['fresh','seek',12345,2])));
 assert.ok(calls.some(x=>JSON.stringify(x)===JSON.stringify(['fresh','gain',24])));assert.equal(fresh.state,'playing');c.release();
});
test('manual realignment preserves pause and never starts an unrelated source',async()=>{
 const calls=[],old=player('old',calls),fresh=player('fresh',calls);factory=async()=>old;
 const c=new C();c.configureAutoPlay(false);await c.create('surface');await c.playUrl('https://v.test/paused.m3u8',{});
 await prepared(old);old.state='paused';old.currentTime=45000;factory=async()=>fresh;
 assert.equal(await c.realignPlayback(),true);await prepared(fresh);
 assert.equal(c.wantsAutoPlay(),false);assert.equal(calls.some(x=>x[0]==='fresh'&&x[1]==='play'),false);
 assert.ok(calls.some(x=>x[0]==='fresh'&&x[1]==='seek'&&x[2]===45000&&x[3]===2));c.release();
});
test('leaving while the replacement is being created cannot revive playback after release',async()=>{
 const calls=[],old=player('old',calls),fresh=player('fresh',calls);factory=async()=>old;
 const c=new C();await c.create('surface');await c.playUrl('https://v.test/video.m3u8',{});await prepared(old);
 let resolve;factory=()=>new Promise(r=>resolve=r);const pending=c.realignPlayback();await flush();c.release();resolve(fresh);
 assert.equal(await pending,false);assert.ok(calls.some(x=>x[0]==='fresh'&&x[1]==='release'));
 assert.equal(calls.some(x=>x[0]==='fresh'&&x[1]==='source'),false);
});
test('a fresh audio/video pipeline is not created until the previous player has finished releasing',async()=>{
 const calls=[],old=player('old',calls),fresh=player('fresh',calls);factory=async()=>old;
 const c=new C();await c.create('surface');await c.playUrl('https://v.test/video.m3u8',{});await prepared(old);
 let finishRelease,creations=0;old.release=()=>new Promise(r=>finishRelease=r);
 factory=async()=>{creations++;return fresh;};const pending=c.realignPlayback();await flush();
 assert.equal(creations,0);finishRelease();assert.equal(await pending,true);assert.equal(creations,1);c.release();
});
