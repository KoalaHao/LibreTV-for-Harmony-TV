import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {DiscoveryPlayback:Playback}=await loadEts('model/DiscoveryPlayback.ets',[["import { Episode, PlayRecord, VideoDetail } from './Types';",'']]);
const episodes=[{index:0,name:'第一集',url:'https://media.test/1.m3u8'},{index:1,name:'第二集',url:'https://media.test/2.m3u8'}];
const detail={episodes:[{index:0,name:'网页',url:'https://player.test/1.html'}],info:{lines:[{name:'网页',episodes:[{index:0,name:'网页',url:'https://player.test/1.html'}]},{name:'原始流',episodes}]}};
test('source buttons select the directly playable HLS line without going through another detail screen',()=>{
 const choice=Playback.choose(detail);assert.equal(choice.lineIndex,1);assert.equal(choice.episode.url,episodes[0].url);assert.equal(choice.positionMs,0);
});
test('same-source history restores episode and position, while invalid history cannot seek into a wrong episode',()=>{
 const choice=Playback.choose(detail,{episode:1,lineIndex:1,positionMs:123456});assert.equal(choice.episodeIndex,1);assert.equal(choice.positionMs,123456);
 const invalid=Playback.choose(detail,{episode:99,lineIndex:99,positionMs:123456});assert.equal(invalid.episodeIndex,0);assert.equal(invalid.positionMs,0);
 assert.equal(Playback.choose({episodes:[],info:{}}),null);
});
