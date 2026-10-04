// Deterministic PCM equivalents of upstream 9e7f88b apps/web/src/audio/*.ts.
// No external encoder or runtime download; run with node scripts/generate-audio.cjs.
const fs = require('node:fs');
const path = require('node:path');
const RATE = 44100;
const out = path.join(__dirname, '../entry/src/main/resources/rawfile');
fs.mkdirSync(out, { recursive: true });
let seed = 72;
const rand = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 * 2 - 1; };
const tone = (hz, duration, gain, type='sine', at=0) => ({hz,duration,gain,type,at});
const noise = (duration,gain,hz,at=0) => ({duration,gain,hz,at,type:'noise'});
const flip = (at) => [tone(720,.035,.018,'triangle',at),tone(420,.055,.016,'triangle',at+.042),noise(.035,.012,4200,at+.064)];
const sounds = {
  round_start:[tone(330,.12,.035,'triangle'),tone(495,.16,.035,'triangle',.12)],
  challenge:[noise(.09,.06,2100),tone(95,.26,.06,'sawtooth')],
  reveal:[...flip(0),...flip(.22),...flip(.44)],
  verdict:[tone(620,.28,.045,'triangle')],
  verdict_bluff:[tone(130,.28,.045,'sawtooth'),noise(.08,.035,1900,.08)],
  revolver_spin:[0,1,2,3].flatMap(i=>[tone(190-i*16,.055,.022,'square',i*.072),noise(.025,.014,3400,i*.072)]),
  trigger_click:[tone(76,.12,.025,'square'),tone(310,.035,.028,'square',.13)],
  gunshot:[noise(.28,.095,1450),tone(58,.38,.075,'sawtooth'),noise(.2,.045,650,.08),tone(118,.2,.032,'sawtooth',.095)],
  empty_click:[tone(260,.035,.038,'square'),tone(410,.055,.024,'triangle',.092)],
  victory:[tone(392,.16,.035,'triangle'),tone(494,.18,.035,'triangle',.16),tone(659,.24,.035,'triangle',.34),noise(.22,.025,3200,.42)],
  card_play:[tone(420,.12,.04)],button_click:[tone(180,.12,.04)]
};
for(const [name,events] of Object.entries(sounds)) {
  const samples = new Float64Array(Math.ceil((Math.max(...events.map(e=>e.at+e.duration))+.02)*RATE));
  for(const e of events) {
    let filtered=0; const alpha=1-Math.exp(-2*Math.PI*e.hz/RATE);
    for(let i=0;i<Math.floor(e.duration*RATE);i++) {
      const p=i/(e.duration*RATE), cycle=i/RATE*e.hz;
      let v=Math.sin(2*Math.PI*cycle);
      if(e.type==='triangle') v=2/Math.PI*Math.asin(v);
      if(e.type==='square') v=v>=0?1:-1;
      if(e.type==='sawtooth') v=2*(cycle%1)-1;
      if(e.type==='noise') { filtered+=alpha*(rand()*Math.pow(1-p,1.8)-filtered); v=filtered; }
      samples[Math.floor(e.at*RATE)+i]+=v*e.gain*Math.pow(.001/e.gain,p);
    }
  }
  const wav=Buffer.alloc(44+samples.length*2);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length-8,4); wav.write('WAVEfmt ',8);
  wav.writeUInt32LE(16,16); wav.writeUInt16LE(1,20); wav.writeUInt16LE(1,22);
  wav.writeUInt32LE(RATE,24); wav.writeUInt32LE(RATE*2,28); wav.writeUInt16LE(2,32); wav.writeUInt16LE(16,34);
  wav.write('data',36); wav.writeUInt32LE(samples.length*2,40);
  samples.forEach((v,i)=>wav.writeInt16LE(Math.round(Math.max(-1,Math.min(1,v))*32767),44+i*2));
  fs.writeFileSync(path.join(out,name+'.wav'),wav);
}
console.log(`Generated ${Object.keys(sounds).length} PCM WAV assets.`);
