const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const ts=require('../backend/node_modules/typescript');
const root=path.join(__dirname,'../entry/src/main/ets');

// Execute actual pure UI methods without the ArkUI DSL; the HAP build checks the DSL/types.
function methods(file,names,globals={}) {
  const source=fs.readFileSync(path.join(root,file),'utf8');
  const bodies=names.map(name=>{
    const start=source.indexOf('  private '+name+'(');assert.ok(start>=0,name);
    const open=source.indexOf('{',start);let depth=1,end=open+1;
    while(depth>0) {if(source[end]==='{')depth++;if(source[end]==='}')depth--;end++;}
    return source.slice(start,end);
  });
  const js=ts.transpileModule('class Subject {'+bodies.join('\n')+'}; module.exports=Subject;',{
    compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
  const mod={exports:{}};new Function('module',...Object.keys(globals),js)(mod,...Object.values(globals));
  return new mod.exports();
}
test('mug presentation only remains active until its private effect expires',()=>{
  const page=methods('pages/GamePage.ets',['isTipsy']);page.getSyncedNow=()=>1000;
  page.store={game:{itemEffect:{type:'TAVERN_MUG_TIPSY',expiresAt:1001}}};assert.equal(page.isTipsy(),true);
  page.store.game.itemEffect.expiresAt=1000;assert.equal(page.isTipsy(),false);
  page.store.game.itemEffect.type='SPYGLASS_RISK';page.store.game.itemEffect.expiresAt=null;assert.equal(page.isTipsy(),false);
  page.store.game=null;assert.equal(page.isTipsy(),false);
});
test('reduced motion stops hand sway and cinematic transitions without removing reveal timing',()=>{
  const hand=methods('components/CardHand.ets',['tipsyProgress']);Object.assign(hand,{tipsy:true,reduceMotion:false,syncedNow:950});
  assert.equal(hand.tipsyProgress(0),1);hand.reduceMotion=true;assert.equal(hand.tipsyProgress(0),0);
  const overlay=methods('components/CinematicOverlay.ets',['motionDuration','isCardFlipped'],{REVEAL_INTRO_MS:500,REVEAL_PER_CARD_MS:750});
  Object.assign(overlay,{reduceMotion:true,lowPower:false,getElapsed:()=>1000});
  assert.equal(overlay.motionDuration(400),0);assert.equal(overlay.isCardFlipped(0),true);assert.equal(overlay.isCardFlipped(1),false);
  overlay.reduceMotion=false;overlay.lowPower=true;assert.equal(overlay.motionDuration(400),0);
  overlay.lowPower=false;assert.equal(overlay.motionDuration(400),400);
});
test('low power actually lowers the page clock refresh rate',()=>{
  const delays=[];const page=methods('pages/GamePage.ets',['startClock'],{setInterval:(_fn,ms)=>{delays.push(ms);return 1}});
  page.stopClock=()=>{};page.store={lowPowerActive:false};page.startClock();page.store.lowPowerActive=true;page.startClock();
  assert.deepEqual(delays,[100,250]);
});
test('share button copies real result stats and handles clipboard failure',async()=>{
  let copied='',reject=false;
  const pasteboard={MIMETYPE_TEXT_PLAIN:'text/plain',createData:(_type,text)=>text,getSystemPasteboard:()=>({setData:async text=>{if(reject)throw Error('clipboard');copied=text}})};
  const page=methods('pages/GamePage.ets',['shareResult'],{pasteboard});
  page.store={game:{summary:{winnerId:'p1',playerCount:4,durationSeconds:88,challengeCount:7,successfulChallenges:3}}};
  page.getPlayerNameById=()=>'胜者';page.getEliminationOrderText=()=>'甲 → 乙';page.shareResult();
  await new Promise(resolve=>setImmediate(resolve));
  assert.match(copied,/胜者.*4 人局.*88 秒.*7 次质疑.*3 次成功.*甲 → 乙/);assert.match(page.shareNotice,/已复制/);
  reject=true;page.shareResult();await new Promise(resolve=>setImmediate(resolve));assert.match(page.shareNotice,/失败/);
});
test('all configured audio assets are valid non-silent PCM and all media references resolve',()=>{
  const resources=path.join(root,'../resources');
  const audio=fs.readFileSync(path.join(root,'audio/AudioManager.ets'),'utf8');
  const files=[...audio.matchAll(/'([a-z_]+\.wav)'/g)].map(m=>m[1]);assert.equal(files.length,12);
  for(const file of files) {
    const wav=fs.readFileSync(path.join(resources,'rawfile',file));
    assert.equal(wav.toString('ascii',0,4),'RIFF');assert.equal(wav.toString('ascii',8,12),'WAVE');
    assert.equal(wav.readUInt32LE(40),wav.length-44);assert.equal(wav.readUInt32LE(24),44100);
    let peak=0;for(let i=44;i<wav.length;i+=2)peak=Math.max(peak,Math.abs(wav.readInt16LE(i)));
    assert.ok(peak>100 && peak<32767,file);
  }
  const visit=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?visit(path.join(dir,e.name)):[path.join(dir,e.name)]);
  const names=new Set(fs.readdirSync(path.join(resources,'base/media')).map(f=>path.parse(f).name));
  for(const file of visit(root).filter(f=>f.endsWith('.ets'))) {
    for(const m of fs.readFileSync(file,'utf8').matchAll(/\$r\('app\.media\.([^']+)'\)/g)) assert.ok(names.has(m[1]),file+': '+m[1]);
  }
});
test('token persistence serializes an earlier slow save before replacement clear',async()=>{
  const source=fs.readFileSync(path.join(root,'store/SessionPersistence.ets'),'utf8');
  const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
  const mod={exports:{}};
  new Function('require','module','exports',js)(id=>id==='@kit.PerformanceAnalysisKit'?{hilog:{warn(){}}}:{},mod,mod.exports);
  const persistence=new mod.exports.SessionPersistence();let token=null,finishSave;const order=[];
  persistence.store={put:async(_key,value)=>{order.push('save');await new Promise(r=>finishSave=r);token=value},delete:async()=>{order.push('clear');token=null},flush:async()=>{}};
  const save=persistence.saveToken('old');const clear=persistence.clearToken();
  await Promise.resolve();assert.deepEqual(order,['save']);finishSave();await Promise.all([save,clear]);
  assert.deepEqual(order,['save','clear']);assert.equal(token,null);
});
