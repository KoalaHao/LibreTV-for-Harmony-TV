import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const {PixelMapCache:Cache}=await loadEts('common/PixelMapCache.ets',[[/^import .*;$/gm,'']]);
const mib=1024*1024;
const pixels=size=>({getPixelBytesNumber:()=>size,release(){throw Error('visible image must remain valid');}});
test('decoded byte budget evicts the least recently used image without releasing visible references',async()=>{
 const a=pixels(32*mib),b=pixels(32*mib),c=pixels(32*mib);
 await Cache.load('a',async()=>a);await Cache.load('b',async()=>b);assert.equal(Cache.get('a'),a);
 await Cache.load('c',async()=>c);assert.equal(Cache.get('b'),undefined);assert.equal(Cache.get('a'),a);assert.equal(Cache.get('c'),c);
});
test('simultaneous cards share the same decode promise and PixelMap',async()=>{
 let count=0,finish;const value=pixels(100);const loader=()=>{count++;return new Promise(resolve=>finish=resolve);};
 const a=Cache.load('shared',loader),b=Cache.load('shared',loader);assert.equal(a,b);
 await Promise.resolve();finish(value);assert.equal(await a,value);assert.equal(await b,value);assert.equal(count,1);
});
test('failed decode can retry; an oversized image is displayed but not retained in the cache',async()=>{
 await assert.rejects(Cache.load('retry',async()=>{throw Error('bad bytes');}));
 const value=pixels(100);assert.equal(await Cache.load('retry',async()=>value),value);
 const large=pixels(65*mib);assert.equal(await Cache.load('oversized',async()=>large),large);assert.equal(Cache.get('oversized'),undefined);
});
test('small icons cannot bypass the cache entry limit',async()=>{
 for(let i=0;i<110;i++)await Cache.load('icon-'+i,async()=>pixels(4));
 assert.equal(Cache.get('icon-0'),undefined);assert.ok(Cache.get('icon-109'));
});
