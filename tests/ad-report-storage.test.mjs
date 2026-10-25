import test from 'node:test';
import assert from 'node:assert/strict';
import {loadEts} from './ets-loader.mjs';
const files=new Map(),directories=new Set(),fds=new Map();let nextFd=0,failIndex=false,failWrite=false;
const missing=()=>{throw Error('missing');};
globalThis.__adFiles={accessSync:p=>files.has(p)||directories.has(p),mkdirSync:p=>directories.add(p),
 readTextSync:p=>files.get(p)??missing(),statSync:p=>({size:new TextEncoder().encode(files.get(p)??missing()).byteLength}),
 openSync:p=>{files.set(p,'');const fd=++nextFd;fds.set(fd,p);return {fd};},
 writeSync:(fd,text)=>{if(failWrite)throw Error('disk full');files.set(fds.get(fd),text);},closeSync:fd=>fds.delete(fd),
 renameSync:(a,b)=>{if(failIndex&&b.endsWith('/index.json'))throw Error('index unavailable');files.set(b,files.get(a));files.delete(a);},
 unlinkSync:p=>files.delete(p),OpenMode:{CREATE:1,TRUNC:2,READ_WRITE:4}};
const {AdReportStorage:S}=await loadEts('data/AdReportStorage.ets',[[/^import .*;$/gm,''],[/^/,'const fs=globalThis.__adFiles;\n']]);
const report=n=>JSON.stringify({schema:1,positionMs:n,context:{title:'影片'}});
S.init('/private');
test('saved marks survive storage reinitialization and retain only the newest twenty reports',()=>{
 for(let i=0;i<23;i++)assert.ok(S.save(report(i)));
 S.init('/private');assert.equal(JSON.parse(S.latest()).positionMs,22);
 assert.equal([...files.keys()].filter(p=>p.includes('/ad-')&&!p.endsWith('index.json')).length,20);
 assert.equal([...files.keys()].filter(p=>p.endsWith('.new')).length,0);assert.equal(fds.size,0);
});
test('index failure keeps the previous record and does not report a successful save or retain orphaned files',()=>{
 const before=new Map(files),latest=S.latest();failIndex=true;assert.equal(S.save(report(99)),'');failIndex=false;
 assert.equal(S.latest(),latest);assert.deepEqual(files,before);assert.equal(fds.size,0);
});
test('disk-full and oversized report failures preserve previous data and close temporary handles',()=>{
 const before=new Map(files);failWrite=true;assert.equal(S.save(report(99)),'');failWrite=false;
 assert.equal(S.save('x'.repeat(524289)),'');assert.deepEqual(files,before);assert.equal(fds.size,0);
});
test('malformed newest record is skipped and a previous valid saved mark remains available',()=>{
 const id=S.save(report(50));files.set('/private/ad-diagnostics/'+id+'.json','{bad json');
 assert.equal(JSON.parse(S.latest()).positionMs,22);
});
