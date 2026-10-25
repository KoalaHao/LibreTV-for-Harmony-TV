import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const {SourceQuality:Quality}=await loadEts('model/SourceQuality.ets');
test('source quality labels preserve explicit dimensions and never guess 1080P from HD or episode updates',()=>{
 assert.equal(Quality.label('1080P蓝光'),'1080P');assert.equal(Quality.label('4K'),'4K');
 assert.equal(Quality.label('3840x2160'),'3840×2160');assert.equal(Quality.label('HD中字'),'HD');
 assert.equal(Quality.label('高清版'),'高清');assert.equal(Quality.label('TC'),'TC');
 assert.equal(Quality.label('更新至第12集'),'');assert.equal(Quality.label(undefined),'');
});
