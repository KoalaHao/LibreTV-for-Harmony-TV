import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {Utils}=await loadEts('common/Utils.ets');
const {PosterCardData}=await loadEts('model/PosterCardData.ets');
globalThis.__searchDiscovery={Utils,PosterCardData};
const {SearchDiscovery:D}=await loadEts('model/SearchDiscovery.ets',[[/^import .*;$/gm,''],[/^/,'const {Utils,PosterCardData}=globalThis.__searchDiscovery;\n']]);
const {CmsClient:Cms}=await loadEts('model/CmsClient.ets',[[/^import .*;$/gm,''],[/^/,'const {Utils}=globalThis.__searchDiscovery;\n']]);
const source={key:'a',name:'A',url:'https://a.test/api.php/provide/vod'};
const result=(year='2026',id='1234567')=>({name:'同名电影',year,pic:'https://a.test/poster.jpg',typeName:'剧情片',area:'中国大陆 / 美国',remarks:'HD',
 items:[{sourceKey:'a',sourceName:'A',vodId:id,name:'同名电影',director:'导演甲 / 导演乙',actor:'演员甲,演员乙',
  content:'<p>简介第一段</p><script>not a synopsis</script><p>第二段</p>',playUrl:'https://a.test/expiring.m3u8?secret=private',playFrom:'line'}]});
test('search selection becomes a discovery entry with the measured poster origin and all known source identities',()=>{
 const film=result(),origin={x:300,y:120,width:185,height:293};
 film.items.push({...film.items[0],sourceKey:'b',vodId:'99'});
 const route=D.entry(film,origin,1000,2000);
 assert.deepEqual(route.origin,origin);assert.equal(route.item.title,film.name);assert.equal(route.searchResult.items.length,2);
 assert.equal(route.searchUpdatedAt,1000);assert.equal(route.openId,2000);assert.equal(route.searchKeyword,film.name);
 assert.equal(D.entry(film,origin,1000,2000,'同名').searchKeyword,'同名');
 assert.equal(route.item.metadataProvider,'cms');assert.notEqual(route.item.id,'1234567');
 assert.equal(route.searchResult.items[0].playUrl,undefined);assert.equal(route.searchResult.items[0].playFrom,undefined);
 assert.doesNotMatch(JSON.stringify(route),/secret=private|not a synopsis/);assert.match(route.searchResult.items[0].content,/第二段/);
});
test('CMS VOD IDs never become Douban IDs; only an explicit valid subject field enables enrichment',()=>{
 const film=result();assert.equal(D.doubanId(film),'');
 film.items[0].doubanId='0';assert.equal(D.entry(film,{x:0,y:0,width:1,height:1},1,2).item.metadataProvider,'cms');
 film.items[0].doubanId='1292052';const item=D.entry(film,{x:0,y:0,width:1,height:1},1,2).item;
 assert.equal(item.id,'1292052');assert.equal(item.metadataProvider,'douban');
 assert.notEqual(D.card(film).id,item.id);
});
test('CMS metadata populates the introduction immediately without inventing ratings or heat',()=>{
 const info=D.info(result());assert.deepEqual(info.countries,['中国大陆','美国']);assert.deepEqual(info.directors,['导演甲','导演乙']);
 assert.deepEqual(info.actors,['演员甲','演员乙']);assert.match(info.description,/简介第一段/);assert.doesNotMatch(info.description,/script|not a synopsis|<p>/);
 assert.equal(info.releaseDate,'2026');assert.equal(info.rating,'');assert.equal(info.shortComments,-1);assert.equal(info.durationMinutes,0);
 assert.equal(info.isSeries,false);assert.equal(D.card({...result(),typeName:'喜剧片'}).isTv,false);
 assert.equal(D.card({...result(),typeName:'动画电影'}).isTv,false);assert.equal(D.card({...result(),typeName:'国产剧',remarks:'全12集'}).isTv,true);
});
test('a source detail enriches text and episode count while retained metadata survives a sparse response',()=>{
 const film={...result(),typeName:'国产剧'},detail={info:{title:film.name,desc:'<p>完整简介</p>',actor:'新演员',doubanId:'1292052'},episodes:[{index:0,name:'1',url:'a'},{index:1,name:'2',url:'b'}]};
 const info=D.enrich(D.info(film,detail),D.info(film));assert.equal(info.description,'完整简介');assert.equal(info.totalEpisodes,2);
 assert.equal(info.releaseDate,'2026');assert.deepEqual(info.actors,['新演员']);assert.deepEqual(info.countries,['中国大陆','美国']);
 assert.equal(D.doubanId(film,detail),'1292052');
});
test('fresh catalogue fields retain their scores and can fill gaps from source metadata without mutating either',()=>{
 const known=PosterCardData.empty('1292052');known.rating='9.7';known.shortComments=12345;known.liveMetadata=true;
 const fallback=D.info(result()),enriched=D.enrich(known,fallback);
 assert.equal(enriched.rating,'9.7');assert.equal(enriched.shortComments,12345);assert.equal(enriched.liveMetadata,true);
 assert.equal(enriched.description,fallback.description);assert.equal(known.description,'');assert.equal(fallback.rating,'');
});
test('resource refresh is scoped to the selected title and year, including the no-year identity case',()=>{
 const selected=result('2026'),old=result('1994','old'),updated=result('2026','new'),other={...result(),name:'另一部影片'};
 assert.deepEqual(D.selected(selected,[old,other,updated]),[updated]);assert.deepEqual(D.selected(selected,[old,other]),[selected]);
 const unknown=result('');assert.deepEqual(D.selected(unknown,[old,updated]),[unknown]);
 assert.deepEqual(D.selected(unknown,[old,{...updated,items:unknown.items}]),[{...updated,items:unknown.items}]);
 assert.notEqual(D.key(selected),D.key(old));
});
test('real CMS parsing carries an explicit subject ID in both search and detail responses',()=>{
 const text=JSON.stringify({list:[{vod_id:1234567,vod_name:'影片',vod_douban_id:1292052,year:'2026',vod_play_url:'正片$https://a.test/a.m3u8',vod_play_from:'hls'}]});
 const item=Cms.parseSearchList(text,source)[0],detail=Cms.parseDetail(text,source);
 assert.equal(item.vodId,'1234567');assert.equal(item.doubanId,'1292052');assert.equal(detail.info.doubanId,'1292052');
 assert.equal(detail.episodes[0].url,'https://a.test/a.m3u8');
});
