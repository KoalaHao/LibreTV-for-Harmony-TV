import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {DetailCache:Cache}=await loadEts('model/DetailCache.ets',[["import { VideoDetail } from './Types';",'']]);
test('probe and selected source share one detail request and the resulting short-lived playback cache',async()=>{
 let calls=0,resolve;const loader=()=>{calls++;return new Promise(r=>resolve=r);};
 const a=Cache.load('source','1',loader),b=Cache.load('source','1',loader);assert.equal(a,b);
 await Promise.resolve();assert.equal(calls,1);const value={episodes:[{url:'https://example.test/a.m3u8'}],info:{title:'影片'}};
 resolve(value);assert.equal(await b,value);assert.equal(await Cache.load('source','1',loader),value);assert.equal(calls,1);
});
test('a failed shared request can be retried instead of leaving a permanently rejected pending entry',async()=>{
 await assert.rejects(Cache.load('source','2',async()=>{throw Error('offline');}));
 const value={episodes:[],info:{title:'重试'}};assert.equal(await Cache.load('source','2',async()=>value),value);
});
