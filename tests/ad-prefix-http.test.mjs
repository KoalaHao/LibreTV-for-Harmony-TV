import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
let observed,destroyed=0,response;
globalThis.__prefixHttp={RequestMethod:{GET:'GET'},HttpDataType:{ARRAY_BUFFER:'bytes',STRING:'text'},createHttp:()=>({
 async request(url,options){observed={url,options};return response??{responseCode:206,result:new ArrayBuffer(564)};},
 destroy(){destroyed++;}
})};
const {HttpClient:H}=await loadEts('net/HttpClient.ets',[[/^import .*;$/gm,''],[/^/,'const http=globalThis.__prefixHttp;\n']]);
test('strict resolution probing asks for only 16 KiB, disables HTTP cache, preserves playback headers and releases the request',async()=>{
 const headers={'User-Agent':'fixture','Referer':'https://v.test/','Authorization':'fixture'};
 const result=await H.getVideoPrefix('https://v.test/a.ts',headers,750);
 assert.equal(result.ok,true);assert.equal(result.bytes.length,564);assert.equal(destroyed,1);
 assert.deepEqual(observed.options.header,{...headers,Range:'bytes=0-16383','Accept-Encoding':'identity'});
 assert.equal(observed.options.maxLimit,16384);assert.equal(observed.options.usingCache,false);
 assert.equal(observed.options.readTimeout,750);assert.equal(observed.options.connectTimeout,750);
 assert.equal(headers.Range,undefined);
});
test('audio tail probes use an explicit verified range because some CDNs mishandle negative suffix ranges',async()=>{
 response={responseCode:206,result:new ArrayBuffer(16384),header:{'Content-Range':'bytes 33616-49999/50000'}};
 let result=await H.getAudioSuffix('https://v.test/a.ts',{'User-Agent':'fixture'},750,50000);
 assert.equal(result.ok,true);assert.equal(result.rangeStart,33616);assert.equal(result.totalBytes,50000);
 assert.equal(observed.options.header.Range,'bytes=33616-49999');assert.equal(observed.options.maxLimit,16384);
 response.header['Content-Range']='bytes 49999-49999/50000';result=await H.getAudioSuffix('https://v.test/a.ts',{},750,50000);
 assert.equal(result.ok,false);assert.equal(result.bytes.length,0);
 response.responseCode=200;result=await H.getAudioSuffix('https://v.test/a.ts',{},750,50000);assert.equal(result.ok,false);
 result=await H.getAudioSuffix('https://v.test/a.ts',{},750,0);assert.equal(result.ok,false);
 response=undefined;
});
