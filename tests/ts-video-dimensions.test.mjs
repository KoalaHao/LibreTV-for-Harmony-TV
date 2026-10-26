import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
import {filmSps,adSps,baselineSps,tsPrefix} from './helpers/h264-headers.mjs';
const {TsVideoDimensions:P}=await loadEts('model/TsVideoDimensions.ets');
const empty={width:0,height:0};
test('SPS crop units distinguish actual film 1918x802 from inserted 1920x1080 headers',()=>{
 assert.deepEqual(P.sps(filmSps),{width:1918,height:802});
 assert.deepEqual(P.sps(adSps),{width:1920,height:1080});
 assert.deepEqual(P.sps(baselineSps(1280,720)),{width:1280,height:720});
});
test('TS video PES payloads are reassembled across packets before reading SPS',()=>{
 assert.deepEqual(P.read(tsPrefix(filmSps,{padding:169})),{width:1918,height:802});
 const prefixed=Buffer.concat([Buffer.alloc(17),tsPrefix(adSps)]);
 assert.deepEqual(P.read(prefixed),{width:1920,height:1080});
 const audio=tsPrefix(adSps);audio[7]=0xc0;
 assert.deepEqual(P.read(audio),empty);
});
test('damaged, scrambled, truncated, unsupported or internally changing streams stay unknown',()=>{
 const scrambled=tsPrefix(adSps);scrambled[3]|=0x80;assert.deepEqual(P.read(scrambled),empty);
 const corrupt=tsPrefix(adSps);corrupt[191]=0x15;assert.deepEqual(P.read(corrupt),empty);
 assert.deepEqual(P.read(tsPrefix(filmSps,{otherSps:adSps})),empty);
 assert.deepEqual(P.read(Buffer.alloc(16385)),empty);
 assert.deepEqual(P.read(Buffer.alloc(563)),empty);
 assert.deepEqual(P.sps(Buffer.from([0x42,1,1,1,1])),empty);
 assert.deepEqual(P.sps(Buffer.from([0x67,100,0,32,0])),empty);
 for(let length=0;length<11;length++)assert.deepEqual(P.sps(adSps.subarray(0,length)),empty);
 // VUI can be outside the prefix; all dimension/crop fields are already complete here.
 assert.deepEqual(P.sps(adSps.subarray(0,11)),{width:1920,height:1080});
});
