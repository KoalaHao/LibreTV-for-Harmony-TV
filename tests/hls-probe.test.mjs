import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');globalThis.__hlsUtils=Utils;
const {HlsProbe:Hls}=await loadEts('model/HlsProbe.ets',[["import { Utils } from '../common/Utils';",'const Utils=globalThis.__hlsUtils;']]);
test('HLS probe selects the largest declared variant and resolves relative and protocol-relative URLs',()=>{
 const info=Hls.parse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=700000,RESOLUTION=640x360\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\n../high/index.m3u8','https://example.test/video/master.m3u8');
 assert.equal(info.width,1920);assert.equal(info.height,1080);assert.equal(info.variant,'https://example.test/high/index.m3u8');
 assert.equal(Hls.parse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n//cdn.test/play.m3u8','https://example.test/x.m3u8').variant,'https://cdn.test/play.m3u8');
});
test('media playlists never infer a resolution from URL names, and encrypted samples are identified',()=>{
 const info=Hls.parse('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:6,\n1080p.ts','https://example.test/x/index.m3u8');
 assert.equal(info.width,0);assert.equal(info.height,0);assert.equal(info.encrypted,true);assert.equal(info.sample,'https://example.test/x/1080p.ts');
 const init=Hls.parse('#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4,\n1.m4s','https://example.test/a.m3u8');assert.equal(init.sample,'https://example.test/init.mp4');
});
test('invalid or excessive playlists and impossible advertised dimensions stay unknown',()=>{
 assert.equal(Hls.parse('<html>blocked</html>','https://example.test/a').valid,false);
 assert.equal(Hls.parse('#EXTM3U\n'+'x'.repeat(131072),'https://example.test/a').valid,false);
 const invalid=Hls.parse('#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=99999x99999,BANDWIDTH=2\na.m3u8','https://example.test/b.m3u8');assert.equal(invalid.width,0);
});
