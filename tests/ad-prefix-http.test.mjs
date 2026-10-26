import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
let observed,destroyed=0;
globalThis.__prefixHttp={RequestMethod:{GET:'GET'},HttpDataType:{ARRAY_BUFFER:'bytes',STRING:'text'},createHttp:()=>({
 async request(url,options){observed={url,options};return{responseCode:206,result:new ArrayBuffer(564)};},
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
