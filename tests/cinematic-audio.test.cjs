const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs');
const ts=require('../backend/node_modules/typescript');
function fixture(){
  const source=fs.readFileSync('entry/src/main/ets/audio/AudioManager.ets','utf8');
  const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
  const module={exports:{}};let vibrations=0;
  new Function('require','module','exports',js)(()=>({vibrator:{startVibration(){vibrations++}}}),module,module.exports);
  const manager=new module.exports.AudioManager(),played=[],stopped=[],pending=[];
  manager.soundPool={play(id){played.push(id);return new Promise(resolve=>pending.push(resolve))},stop(id){stopped.push(id);return Promise.resolve()}};
  ['challenge','reveal','verdict','verdictBluff','revolverSpin','triggerClick','gunshot','emptyClick'].forEach((name,i)=>{manager.soundIds.set(name,i);manager.readyIds.add(i)});
  return {manager,played,stopped,pending,vibrations:()=>vibrations};
}
test('native cues map to challenge, reveal, both verdicts, spin, trigger and both results',()=>{
  const f=fixture();f.manager.playChallenge();f.manager.playReveal();f.manager.playVerdict(false);f.manager.playVerdict(true);f.manager.playRevolverSpin();f.manager.playTriggerClick();f.manager.playGunshot();f.manager.playEmptyClick();
  assert.deepEqual(f.played,[0,1,2,3,4,5,6,7]);assert.equal(f.vibrations(),1);
});
test('mute stops active and pending native streams and suppresses future sound/vibration',async()=>{
  const f=fixture();f.manager.playChallenge();f.pending.shift()(41);await Promise.resolve();
  f.manager.playReveal();f.manager.setEnabled(false);assert.deepEqual(f.stopped,[41]);
  f.pending.shift()(42);await Promise.resolve();assert.deepEqual(f.stopped,[41,42]);
  f.manager.playGunshot();f.manager.playEmptyClick();assert.deepEqual(f.played,[0,1]);assert.equal(f.vibrations(),0);
});
