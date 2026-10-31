import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');
const base='https://video.test/share/42';
test('relative var main addresses cannot absorb an earlier CDN script tag',()=>{
 const html='<script src="https://cdn.test/hls.js"></script>\n<script>var main = "/2026/video/index.m3u8?sign=secret";</script>';
 assert.equal(Utils.mediaUrlFromPage(html,base),'https://video.test/2026/video/index.m3u8?sign=secret');
});
test('const URLs, JSON slash escapes, HTML entities and protocol-relative media retain query parameters',()=>{
 assert.equal(Utils.mediaUrlFromPage('const url = "../f/index.m3u8?key=a&amp;x=b";',base),'https://video.test/f/index.m3u8?key=a&x=b');
 assert.equal(Utils.mediaUrlFromPage('{"url":"https:\\/\\/cdn.test\\/x.m3u8?key=a\\u0026x=b"}',base),'https://cdn.test/x.m3u8?key=a&x=b');
 assert.equal(Utils.mediaUrlFromPage('let videoUrl="//cdn.test/x.mp4"',base),'https://cdn.test/x.mp4');
});
test('quoted source tags and standalone quoted media URLs are parsed without running scripts',()=>{
 assert.equal(Utils.mediaUrlFromPage('<video><source src="/film.mp4?x=1"></video>',base),'https://video.test/film.mp4?x=1');
 assert.equal(Utils.mediaUrlFromPage('player.load("https://cdn.test/film.m3u8")',base),'https://cdn.test/film.m3u8');
});
test('unrelated script text and unsupported URI schemes are never handed to the player as media URLs',()=>{
 for(const html of ['<script src="https://cdn.test/hls.js"></script>\n// no video .m3u8',
  'const url="javascript:evil.m3u8"','var main="data:video/x.m3u8"','const url="https://x.test/<script>.m3u8"']){
  assert.equal(Utils.mediaUrlFromPage(html,base),'');
 }
});
