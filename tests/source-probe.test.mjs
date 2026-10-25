import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');globalThis.__sourceProbeUtils=Utils;
const {HlsProbe}=await loadEts('model/HlsProbe.ets',[["import { Utils } from '../common/Utils';",'const Utils=globalThis.__sourceProbeUtils;']]);
globalThis.__sourceHls=HlsProbe;
let mode='master',manifestCalls=0,sampleCalls=0;
globalThis.__sourceCms={detail:async()=>({episodes:[{url:'https://media.test/index.m3u8'}],info:{title:'影片'}})};
globalThis.__sourceDetail={load:async(k,id,loader)=>loader()};
globalThis.__sourceHttp={UA:'test',originOf:()=> 'https://media.test/',getTextLimited:async()=>{
 manifestCalls++;return {ok:true,status:200,text:mode==='master'?'#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=1920x1080,BANDWIDTH=4000000\n1080.m3u8':'#EXTM3U\n'+(mode==='encrypted'?'#EXT-X-KEY:METHOD=AES-128,URI="key"\n':'')+'#EXTINF:6,\n1.ts'};
},getProbeBytes:async()=>{sampleCalls++;return {ok:true,bytes:new Uint8Array([1,2,3])};}};
globalThis.__sourceMetadata={dimensions:async()=>({width:1280,height:544})};
const {SourceProbe:Probe}=await loadEts('model/SourceProbe.ets',[
 ["import { SearchItem, VodSource, VideoDetail } from './Types';",''],
 ["import { CmsClient } from './CmsClient';",'const CmsClient=globalThis.__sourceCms;'],
 ["import { DetailCache } from './DetailCache';",'const DetailCache=globalThis.__sourceDetail;'],
 ["import { HttpClient } from '../net/HttpClient';",'const HttpClient=globalThis.__sourceHttp;'],
 ["import { HlsProbe } from './HlsProbe';",'const HlsProbe=globalThis.__sourceHls;'],
 ["import { StreamMetadataProbe } from './StreamMetadataProbe';",'const StreamMetadataProbe=globalThis.__sourceMetadata;']
]);
const item={sourceKey:'a',sourceName:'A',vodId:'1',name:'影片'},source={key:'a',url:'https://source.test'};
test('declared master dimensions are identified as an advertised upper bound, without downloading segments',async()=>{
 const result=await Probe.run(item,source,()=>true);assert.equal(result.width,1920);assert.equal(result.resolutionSource,'manifest');assert.equal(sampleCalls,0);
});
test('unencrypted media samples can provide encoded dimensions, while encrypted samples are never fetched for metadata',async()=>{
 mode='media';const result=await Probe.run(item,source,()=>true);assert.equal(result.width,1280);assert.equal(result.height,544);assert.equal(result.resolutionSource,'stream');assert.equal(sampleCalls,1);
 mode='encrypted';const encrypted=await Probe.run(item,source,()=>true);assert.equal(encrypted.width,0);assert.equal(encrypted.status,'ok');assert.equal(sampleCalls,1);
});
test('a page that is no longer visible stops after the shared CMS request instead of starting media traffic',async()=>{
 const before=manifestCalls;assert.equal(await Probe.run(item,source,()=>false),null);assert.equal(manifestCalls,before);
});
