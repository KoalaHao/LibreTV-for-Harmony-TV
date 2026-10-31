export function audioTsPrefix(rate=48000,{rates=[rate,rate,rate,rate],pid=257}={}){
 const table=[96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350];
 const frames=rates.flatMap(hz=>{
  const size=90,frame=Array(size).fill(0x35),index=table.indexOf(hz);
  frame.splice(0,7,0xff,0xf1,(1<<6)|(index<<2),0x80|((size>>11)&3),(size>>3)&255,((size&7)<<5)|31,0xfc);
  return frame;
 });
 const pes=[0,0,1,0xc0,0,0,0x80,0,0,...frames],packets=[];
 for(let off=0,counter=0;off<pes.length;off+=184,counter++){
  const p=new Uint8Array(188).fill(0xff);p.set([0x47,((pid>>8)&31)|(off===0?64:0),pid&255,0x10|(counter&15)]);
  p.set(pes.slice(off,off+184),4);packets.push(...p);
 }
 while(packets.length<564)packets.push(...new Uint8Array([0x47,0x1f,0xff,0x10,...Array(184).fill(0xff)]));
 return new Uint8Array(packets);
}
