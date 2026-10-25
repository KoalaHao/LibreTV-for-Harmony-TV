import test from 'node:test';
import assert from 'node:assert/strict';
import { loadEts } from './ets-loader.mjs';
const {DiscoveryLayout:Layout}=await loadEts('model/DiscoveryLayout.ets');
test('three TV columns remain separated and within the usable viewport',()=>{
 for(const [w,h] of [[960,600],[1280,720],[1920,1080]]) {
  const c=Layout.columns(w,h);assert.ok(c.poster.x+c.poster.width<c.metadataX);
  assert.ok(c.metadataX+c.metadataWidth<c.resultsX);assert.ok(c.resultsX+c.resultsWidth<=w-39);
  assert.ok(c.poster.y+c.poster.height<h);assert.ok(c.bodyY+c.bodyHeight<=h-23);assert.ok(c.metadataWidth>=200);
 }
});
test('unmeasured or invalid viewports have a stable TV fallback',()=>{
 assert.deepEqual(Layout.columns(NaN,0),Layout.columns(1280,720));
 assert.ok(Number.isFinite(Layout.columns(Infinity,Infinity).poster.width));
});
