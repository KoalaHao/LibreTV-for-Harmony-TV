import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const { RecommendYears } = await loadEts('common/RecommendYears.ets');
const urls = [];
globalThis.__yearHttp = {
  UA: 'test',
  async getText(url) {
    urls.push(new URL(url));
    return { ok: true, text: JSON.stringify({ data: urls.length === 1 ? [] : [{ id: '2019', title: 'A', cover: 'https://example.test/a.jpg', rate: '8' }] }) };
  }
};
const { DoubanClient } = await loadEts('model/DoubanClient.ets', [
  ["import { HttpClient } from '../net/HttpClient';", 'const HttpClient = globalThis.__yearHttp;'],
  ["import { RecommendItem } from './Types';", '']
]);
test('year/decade ranges stop at the current year and reject malformed/future selections', () => {
  assert.equal(RecommendYears.range('2026', 2026), '2026,2026');
  assert.equal(RecommendYears.range('2020年代', 2026), '2020,2026');
  assert.equal(RecommendYears.range('2010年代', 2026), '2010,2019');
  assert.equal(RecommendYears.range('更早', 2026), '1900,1969');
  for (const value of ['', '全部', '2030', '2011年代', '2026,9999']) assert.equal(RecommendYears.range(value, 2026), '');
  assert.equal(RecommendYears.options(2027)[1], '2027');
});
test('provider pagination and fallback rating ranges preserve year + genre + country filters', async () => {
  await DoubanClient.browse('电影', '动作', '中国大陆', 'R', 40, '2010,2019');
  assert.equal(urls.length, 2);
  for (const url of urls) {
    assert.equal(url.searchParams.get('year_range'), '2010,2019');
    assert.equal(url.searchParams.get('genres'), '动作');
    assert.equal(url.searchParams.get('countries'), '中国大陆');
    assert.equal(url.searchParams.get('start'), '40');
  }
});
