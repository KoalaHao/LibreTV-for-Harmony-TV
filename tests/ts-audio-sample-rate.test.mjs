import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
import {audioTsPrefix} from './helpers/aac-headers.mjs';
import {tsPrefix,filmSps} from './helpers/h264-headers.mjs';
const {TsAudioSampleRate:A}=await loadEts('model/TsAudioSampleRate.ets');
test('AAC sampling frequency is read from consecutive ADTS frames in audio PES, including unaligned tail samples',()=>{
 for(const rate of [44100,48000,32000,96000]){
  const bytes=audioTsPrefix(rate);assert.equal(A.read(bytes),rate);
  assert.equal(A.read(new Uint8Array([12,34,56,...bytes])),rate);
 }
});
test('video data and invalid, encrypted, discontinuous, mixed-rate or multi-audio samples stay unknown',()=>{
 assert.equal(A.read(tsPrefix(filmSps)),0);
 assert.equal(A.read(new Uint8Array(20000)),0);
 assert.equal(A.read(audioTsPrefix(48000,{rates:[48000]})),0);
 assert.equal(A.read(audioTsPrefix(48000,{rates:[48000,48000,44100,44100]})),0);
 for(const flag of ['encrypted','error','counter']){
  const b=audioTsPrefix();if(flag==='encrypted')b[3]|=0x80;else if(flag==='error')b[1]|=0x80;else b[191]=0x13;
  assert.equal(A.read(b),0,flag);
 }
 assert.equal(A.read(new Uint8Array([...audioTsPrefix(),...audioTsPrefix(48000,{pid:258})])),0);
});
