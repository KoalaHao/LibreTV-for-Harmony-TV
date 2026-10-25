import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
let releases=0,mode='valid';
globalThis.__probeMedia={createAVMetadataExtractor:async()=>({dataSrc:null,async fetchMetadata(){
 if(mode==='unsupported')throw Error('unsupported');
 if(mode==='timeout')return new Promise(()=>{});
 const buffer=new ArrayBuffer(4);assert.equal(this.dataSrc.callback(buffer,2,0),2);assert.deepEqual([...new Uint8Array(buffer).slice(0,2)],[1,2]);
 assert.equal(this.dataSrc.callback(buffer,4,3),-1);return {videoWidth:'1280',videoHeight:'544'};
},async release(){releases++;}})};
const {StreamMetadataProbe:Probe}=await loadEts('model/StreamMetadataProbe.ets',[["import { media } from '@kit.MediaKit';",'const media=globalThis.__probeMedia;']]);
test('bounded media prefixes expose only available bytes and release the native metadata extractor',async()=>{
 assert.deepEqual(await Probe.dimensions(new Uint8Array([1,2,3])),{width:1280,height:544});assert.equal(releases,1);
 mode='unsupported';assert.deepEqual(await Probe.dimensions(new Uint8Array([1,2,3])),{width:0,height:0});assert.equal(releases,2);
});
test('API-11 metadata probing times out and releases resources without needing the API-26 timeout overload',async()=>{
 mode='timeout';assert.deepEqual(await Probe.dimensions(new Uint8Array([1,2,3])),{width:0,height:0});assert.equal(releases,3);
});
