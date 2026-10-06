const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('fs'),path=require('path');
const ts=require('../backend/node_modules/typescript');
const root=path.resolve('entry/src/main/ets');
const source=fs.readFileSync(path.join(root,'components/CinematicMotion.ets'),'utf8');
const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const mod={exports:{}};new Function('module','exports',js)(mod,mod.exports);
const {revealProgress,keyframe,cinematicIdentity}=mod.exports;
test('1 and 3 cards retain web logical flip times, independent 90ms delays and permanent fronts',()=>{
  for(const count of [1,3])for(let index=0;index<count;index++){
    const logical=500+index*750,visual=logical+index*90;
    assert.equal(revealProgress(logical-1,index,true),0);
    assert.equal(revealProgress(logical,index,true),1);
    assert.equal(revealProgress(visual,index,false),0);
    assert.ok(revealProgress(visual+125,index,false)>0.5);
    assert.equal(revealProgress(visual+500,index,false),1);
    for(const elapsed of [4000,6000,10000])assert.equal(revealProgress(elapsed,index,false),1);
  }
});
test('CSS keyframe endpoints and overshoot are retained without changing server duration',()=>{
  assert.equal(keyframe(377,650,[0,.58,1],[.82,1.08,1],[.2,1,.24,1]),1.08);
  assert.equal(keyframe(76,380,[0,.2,.4,.6,.8,1],[0,-8,7,-4,3,0]),-8);
  assert.equal(keyframe(137.5,550,[0,.25,.5,.75,1],[0,-5,5,-2,0]),-5);
  assert.equal(keyframe(340,340,[0,.76,1],[-65,10,0],[.2,.8,.24,1]),0);
  assert.equal(keyframe(518.4,720,[0,.48,.72,1],[0,0,5,0],[.2,.9,.2,1]),5);
  assert.equal(keyframe(102,300,[0,.34,1],[0,-18,0],[.15,.85,.28,1]),-18);
  assert.equal(keyframe(480,480,[0,.12,1],[0,1,0]),0);
  assert.equal(keyframe(720,720,[0,.24,1],[0,.34,0]),0);
});
function overlayFixture(){
  const s=fs.readFileSync(path.join(root,'components/CinematicOverlay.ets'),'utf8');
  const names=['phaseIdentity','stopPhaseAnimation','startPhaseAnimation','getDuration'];
  const bodies=names.map(name=>{const a=s.indexOf('  private '+name+'(');let b=s.indexOf('{',a)+1,d=1;while(d){if(s[b]==='{')d++;if(s[b]==='}')d--;b++;}return s.slice(a,b)});
  const code=ts.transpileModule('class Overlay {'+bodies.join('\n')+'};module.exports=Overlay;', {compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
  const m={exports:{}};let now=10000;
  new Function('module','cinematicIdentity','Date',code)(m,cinematicIdentity,{now:()=>now});
  const o=new m.exports(),created=[];
  Object.assign(o,{game:{matchId:'one',roundNumber:1,phase:'REVEAL',phaseStartedAt:9000,phaseEndsAt:12750},activeIdentity:'',animator:null,clockOffset:0,reduceMotion:false,lowPower:false,disposed:false,
    isVisible:()=>true,getUIContext:()=>({createAnimator:options=>{const a={options,onframe(){},play(){},cancel(){this.cancelled=true}};created.push(a);return a}})});
  return {o,created,setNow:n=>now=n};
}
test('native animator seeks on resume, ignores duplicate snapshots and fences obsolete frames',()=>{
  const {o,created}=overlayFixture();o.startPhaseAnimation();
  assert.equal(o.animationElapsed,1000);assert.equal(created[0].options.delay,-1000);
  assert.equal(created[0].options.duration,3750);assert.equal(created[0].options.easing,'linear');
  o.game={...o.game,sequence:99};o.startPhaseAnimation();assert.equal(created.length,1);
  created[0].onframe(1200);created[0].onframe(1100);assert.equal(o.animationElapsed,1200,'never turns backwards');
  const stale=created[0].onframe;o.game={...o.game,phase:'VERDICT',phaseStartedAt:10000,phaseEndsAt:11300};o.startPhaseAnimation();stale(3750);
  assert.equal(o.animationElapsed,0);assert.equal(created.length,2);
});
test('later trigger/result and new match each receive independent native playback',()=>{
  const {o,created}=overlayFixture();o.game.phase='PUNISHMENT_TRIGGER';o.startPhaseAnimation();
  o.game={...o.game,phaseStartedAt:9900};o.startPhaseAnimation();assert.equal(created.length,2);
  o.game={...o.game,matchId:'two'};o.startPhaseAnimation();assert.equal(created.length,3);
  o.reduceMotion=true;o.startPhaseAnimation(true);assert.equal(created.length,3);assert.equal(o.animationElapsed,100);
});
test('static cards are structurally independent and no face uses cover cropping or cross-fades',()=>{
  const cards=fs.readFileSync(path.join(root,'components/RevealCard.ets'),'utf8');
  const staticCard=cards.slice(cards.indexOf('export struct StaticRevealedCard'));
  assert.doesNotMatch(staticCard,/rotate\(|animation\(|concealed:/);
  assert.match(cards,/angle: this.progress \* 180 - 180/);
  assert.doesNotMatch(cards,/\.animation\(/);
  const art=fs.readFileSync(path.join(root,'components/CardArtwork.ets'),'utf8');
  assert.match(art,/ImageFit.Contain/);assert.doesNotMatch(art,/ImageFit.Cover/);
});
