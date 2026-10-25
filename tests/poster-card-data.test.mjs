import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadEts } from './ets-loader.mjs';
const { PosterCardData: Data } = await loadEts('model/PosterCardData.ets');
const series = JSON.parse(await readFile(new URL('./fixtures/douban-series.json', import.meta.url), 'utf8'));
const movie = JSON.parse(await readFile(new URL('./fixtures/douban-movie.json', import.meta.url), 'utf8'));

test('real series response supplies countries, genres, first broadcast, episodes and short-comment heat', () => {
  const info = Data.parse(JSON.stringify(series), '35588177');
  assert.deepEqual(info.countries, ['中国大陆']);
  assert.deepEqual(info.genres, ['剧情', '家庭', '犯罪']);
  assert.equal(info.releaseDate, '2023.04.22');
  assert.equal(Data.footerRight(info), '12集');
  assert.equal(info.shortComments, 412356);
  assert.notEqual(info.shortComments, series.rating.count);
  assert.notEqual(info.shortComments, series.review_count);
  assert.equal(Data.heatTier(info.shortComments), 4);
});
test('real movie response uses runtime, never an episode count, and displays a plain date', () => {
  const info = Data.parse(JSON.stringify(movie), '1292052', true);
  assert.equal(info.isSeries, false);
  assert.equal(Data.footerRight(info), '142分钟');
  assert.equal(info.releaseDate, '2026.08.28');
  assert.equal(info.rating, '9.7');
});
test('partial metadata stays unknown and never derives comment totals from rating or review counts', () => {
  const partial = { id: '35588177', is_tv: true, rating: { count: 500000, value: null }, review_count: 99999, year: '2023' };
  const info = Data.parse(JSON.stringify(partial), '35588177');
  assert.equal(info.shortComments, -1);
  assert.equal(Data.heatTier(info.shortComments), -1);
  assert.equal(info.rating, '');
  assert.equal(info.releaseDate, '2023');
  assert.equal(Data.footerRight(info), '剧集');
  assert.equal(Data.footerRight(Data.empty()), '电影');
  assert.equal(Data.parse(JSON.stringify({ ...partial, comment_count: 0 }), '35588177').shortComments, 0);
});
test('tier boundaries keep missing data distinct from zero, with fixed cumulative thresholds', () => {
  const pairs = [[-1,-1],[NaN,-1],[0,0],[999,0],[1000,1],[9999,1],[10000,2],[49999,2],[50000,3],[199999,3],[200000,4]];
  for (const [count,tier] of pairs) assert.equal(Data.heatTier(count), tier);
});
test('invalid IDs, challenge HTML and mismatched subject data are rejected', () => {
  assert.equal(Data.parse('<html>载入中</html>', '35588177'), null);
  assert.equal(Data.parse(JSON.stringify(series), '1292052'), null);
  assert.equal(Data.parse(JSON.stringify(series), '431299'), null);
});
test('countries deduplicate, unknown flags stay unknown, and invalid dates are not invented', () => {
  const info = Data.parse(JSON.stringify({ ...series, countries: ['中国大陆','中国大陆','美国'], pubdate: ['2023-02-30'], year: '' }), '35588177');
  assert.deepEqual(info.countries, ['中国大陆','美国']);
  assert.equal(info.releaseDate, '');
  assert.equal(Data.regionCode('中国大陆'), 'cn');
  assert.equal(Data.regionCode('中国香港'), 'hk');
  assert.equal(Data.regionCode('未知地区'), '');
  assert.equal(Data.duration('2小时53分钟'), 173);
});
test('cache roundtrip keeps stable fields and discards every score and short-comment count', () => {
  const info = Data.parse(JSON.stringify(series), '35588177');
  const stable = Data.stable(info);
  assert.equal('rating' in stable, false);
  assert.equal('shortComments' in stable, false);
  assert.deepEqual(Data.restore(JSON.stringify(stable), '35588177'), Data.fromStatic(info));
  assert.deepEqual(Data.restore(JSON.stringify(info), '35588177'), Data.fromStatic(info));
  assert.equal(Data.restore(JSON.stringify(info), '1292052'), null);
  assert.equal(Data.restore(JSON.stringify(Data.empty('35588177')), '35588177').shortComments, -1);
});
test('footer follows the first region with muted colours and defaults to grey for unknown regions', () => {
  assert.equal(Data.footerColor(['中国大陆']), '#61383B');
  assert.equal(Data.footerColor(['韩国']), '#3C5964');
  assert.equal(Data.footerColor(['日本']), '#695265');
  assert.equal(Data.footerColor(['韩国','日本']), Data.footerColor(['韩国']));
  assert.equal(Data.footerColor(['未知地区']), '#363940');
  assert.equal(Data.footerColor([]), '#363940');
  for (const region of ['中国大陆','韩国','日本','美国','英国','法国','德国','印度','巴西']) {
    const c=Data.footerColor([region]).slice(1).match(/../g).map(v=>parseInt(v,16));
    assert.ok(Math.max(...c)<=110);
    assert.ok((Math.max(...c)-Math.min(...c))/Math.max(...c)<0.5);
  }
});
test('the public abstract supplies stable fields without reusing its score or inventing heat', () => {
  const info=Data.parseAbstract(JSON.stringify({r:0,subject:{id:'35588177',is_tv:true,region:'中国大陆 / 韩国',types:['剧情'],release_year:'2023',duration:'60分钟',episodes_count:'12',rate:'9.4',star:5}}), '35588177');
  assert.deepEqual(info.countries,['中国大陆','韩国']);
  assert.equal(info.releaseDate,'2023');assert.equal(Data.footerRight(info),'12集');
  assert.equal(info.rating,'');assert.equal(info.shortComments,-1);assert.equal(info.liveMetadata,false);
  assert.equal(Data.parseAbstract('{"r":1}', '35588177'),null);
  assert.equal(Data.parseAbstract('{"r":0,"subject":{"id":"1292052"}}', '35588177'),null);
});
test('HTTP 400 with Douban code 1309 is a rate limit, not a movie-versus-series mismatch', () => {
  assert.equal(Data.isRateLimited(400,JSON.stringify({msg:'subject_ip_rate_limit',code:1309})),true);
  assert.equal(Data.isRateLimited(429,''),true);
  assert.equal(Data.isRateLimited(400,JSON.stringify({msg:'traversal_error',code:404})),false);
  assert.equal(Data.isRateLimited(404,''),false);
});
test('expanded film metadata survives catalogue caching without inventing absent fields', () => {
  const info=Data.parse(JSON.stringify({...series,original_title:'Original title',intro:'剧情简介样例。',directors:[{name:'导演甲'}],actors:[{name:'主演乙'},{name:'主演丙'}]}),'35588177');
  assert.equal(info.detailsLoaded,true);assert.equal(info.description,'剧情简介样例。');
  assert.deepEqual(info.directors,['导演甲']);assert.deepEqual(info.actors,['主演乙','主演丙']);
  const restored=Data.restore(JSON.stringify(Data.stable(info)),'35588177');
  assert.equal(restored.originalTitle,'Original title');assert.deepEqual(restored.actors,info.actors);
  assert.equal(Data.restore('{"subjectId":"35588177"}','35588177').detailsLoaded,false);
});
