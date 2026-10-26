// Header-only fixtures: no video frames, audio, source URLs or user data.
export const filmSps = Buffer.from('67640028acd94078067ea23016a020202800001f480005dc0078c18cb000','hex');
export const adSps = Buffer.from('67640032acd980780227e5c05a808080a0000003002000000781e306334000','hex');
export function baselineSps(width,height) {
 let bits=''; const read=(v,n)=>bits+=v.toString(2).padStart(n,'0');
 const ue=v=>{const b=(v+1).toString(2);bits+='0'.repeat(b.length-1)+b;};
 read(66,8);read(0,8);read(40,8);ue(0);ue(0);ue(0);ue(0);ue(1);read(0,1);
 ue(Math.ceil(width/16)-1);ue(Math.ceil(height/16)-1);read(1,1);read(1,1);
 const x=(Math.ceil(width/16)*16-width)/2,y=(Math.ceil(height/16)*16-height)/2;
 read(x||y?1:0,1);if(x||y){ue(0);ue(x);ue(0);ue(y);}
 bits+='1';while(bits.length%8)bits+='0';
 return Buffer.from([0x67,...Array.from({length:bits.length/8},(_,i)=>parseInt(bits.slice(i*8,i*8+8),2))]);
}
export function tsPrefix(sps,{padding=0,otherSps=null}={}) {
 const es=Buffer.concat([Buffer.alloc(padding,0xff),Buffer.from([0,0,1]),sps,Buffer.from([0,0,1,0x68,0x80]),
  ...(otherSps?[Buffer.from([0,0,1]),otherSps,Buffer.from([0,0,1,0x68,0x80])]:[])]);
 const pes=Buffer.concat([Buffer.from([0,0,1,0xe0,0,0,0x80,0,0]),es]);
 const n=Math.max(3,Math.ceil(pes.length/184)),out=Buffer.alloc(n*188,0xff);
 for(let i=0;i<n;i++){
  out.set([0x47,i===0?0x41:0x01,0,0x10+(i%16)],i*188);
  out.set(pes.subarray(i*184,(i+1)*184),i*188+4);
 }
 return out;
}
