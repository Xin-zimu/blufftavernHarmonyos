// Node regression tests run the real ArkTS parser/store/manager, with platform I/O mocked.
// Run: node --test tests/harmony-session.test.cjs (backend dependencies must be installed).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('../backend/node_modules/typescript');
const root = process.env.ARKTS_TEST_ROOT || path.join(__dirname,'../entry/src/main/ets');

function fixture() {
  let now=10000, timerId=0;
  const timers=new Map(), cache=new Map();
  class Transport {
    connected=false; sent=[];
    constructor(push,open,close) { Object.assign(this,{push,open,close}); }
    connect() { this.connected=true; this.open(); }
    disconnect() { this.connected=false; this.close(false); }
    isConnected() { return this.connected; }
    isConnecting() { return false; }
    send(event,payload,callback) { this.sent.push({event,payload,callback}); }
  }
  function load(file) {
    file=path.resolve(file); if(cache.has(file)) return cache.get(file).exports;
    const source=fs.readFileSync(file,'utf8').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,'');
    const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
    const mod={exports:{}}; cache.set(file,mod);
    const req=id=> {
      if(id==='@kit.PerformanceAnalysisKit') return {hilog:{info(){},warn(){}}};
      if(id.endsWith('WsTransport')) return {WsTransport:Transport};
      if(id.endsWith('SessionPersistence')) return {};
      return load(path.resolve(path.dirname(file),id+'.ets'));
    };
    new Function('require','module','exports','Date','setTimeout','clearTimeout',js)(req,mod,mod.exports,
      {now:()=>now},(fn,ms)=>{timers.set(++timerId,{fn,at:now+ms});return timerId},id=>timers.delete(id));
    return mod.exports;
  }
  const {SessionStore}=load(path.join(root,'store/SessionStore.ets'));
  const {SocketManager}=load(path.join(root,'net/SocketManager.ets'));
  const {parseGameSnapshot}=load(path.join(root,'model/Parsers.ets'));
  const store=new SessionStore(), persistence={clears:0,saved:[],saveToken(t){this.saved.push(t)},clearToken(){this.clears++}};
  const manager=new SocketManager(store,persistence);
  manager.connect('http://test.invalid');
  store.enterRoom({code:'ABC123',status:'PLAYING'},'p1','token-A');
  const room=(status='PLAYING')=>({code:'ABC123',status});
  const snap=(sequence,phase='TURN',matchId='match-A')=>parseGameSnapshot({sequence,phase,matchId,serverNow:now,hand:['A'],phaseEndsAt:phase==='GAME_OVER'?null:now+1000});
  const success=(game)=>({ok:true,data:{room:room(),playerId:'p1',sessionToken:'token-A',game}});
  const advance=ms=> {now+=ms;for(const [id,t] of [...timers]) if(t.at<=now){timers.delete(id);t.fn()}};
  return {load,store,manager,persistence,transport:manager.transport,room,snap,success,advance,timers};
}
for(const code of ['TIMEOUT','DISCONNECTED','SEND_FAILED','RATE_LIMITED','SERVER_ERROR']) {
  test(`resume preserves token after ${code}, retries, and accepts authoritative state`,()=>{
    const f=fixture(); f.manager.requestAuthoritativeResync();
    f.transport.sent[0].callback({ok:false,error:{code,message:'temporary'}});
    assert.equal(f.store.sessionToken,'token-A'); assert.equal(f.persistence.clears,0);
    f.advance(4000); assert.equal(f.transport.sent.length,2);
    f.transport.sent[1].callback(f.success(f.snap(5)));
    assert.equal(f.store.game.sequence,5); assert.equal(f.manager.resumeInFlight,false);
  });
}
test('disconnected resync does not consume throttle or token; reconnect resumes',()=>{
  const f=fixture(); f.transport.connected=false; const previous=f.manager.lastResyncAt;
  f.manager.requestAuthoritativeResync(); assert.equal(f.transport.sent.length,0);
  assert.equal(f.store.sessionToken,'token-A'); assert.equal(f.manager.lastResyncAt,previous);
  f.transport.connected=true; f.transport.open(); assert.equal(f.transport.sent.length,1);
});
test('resync has at most one pending request and throttles successful requests',()=>{
  const f=fixture(); f.manager.requestAuthoritativeResync();f.advance(5000);f.manager.requestAuthoritativeResync();
  assert.equal(f.transport.sent.length,1);
  f.transport.sent[0].callback(f.success(f.snap(3))); f.manager.requestAuthoritativeResync();
  assert.equal(f.transport.sent.length,2);
  f.transport.sent[1].callback(f.success(f.snap(4))); f.manager.requestAuthoritativeResync();
  assert.equal(f.transport.sent.length,2);
});
test('SESSION_NOT_FOUND clears game, room and persistent token',()=>{
  const f=fixture();f.manager.applyGameSnapshot(f.snap(30));f.manager.requestAuthoritativeResync();
  f.transport.sent[0].callback({ok:false,error:{code:'SESSION_NOT_FOUND',message:'expired'}});
  assert.equal(f.store.room,null);assert.equal(f.store.game,null);assert.equal(f.store.sessionToken,null);
  assert.equal(f.persistence.clears,1);f.advance(20000);assert.equal(f.transport.sent.length,1);
});
test('replacement fences late resume, command ACK, old transport callbacks and foreground connect',()=>{
  const f=fixture();f.manager.requestAuthoritativeResync();f.manager.playCards([0]);
  const lateResume=f.transport.sent[0].callback, latePlay=f.transport.sent[1].callback;
  f.transport.push('session:replaced','replaced');
  lateResume(f.success(f.snap(5)));latePlay({ok:true,data:f.snap(40)});
  f.transport.open();f.transport.push('room:state',f.room());f.transport.push('game:snapshot',f.snap(99));
  f.manager.connect('http://test.invalid'); f.manager.requestAuthoritativeResync();f.advance(20000);
  assert.equal(f.store.sessionToken,null);assert.equal(f.store.room,null);assert.equal(f.store.game,null);
  assert.equal(f.persistence.saved.length,0);assert.equal(f.manager.transport.sent.length,0);
  // Explicit fresh membership is still allowed; no recovery of token-A.
  f.manager.createRoom('新玩家');
  f.manager.transport.sent[0].callback({ok:true,data:{room:{code:'NEW123',status:'LOBBY'},playerId:'p2',sessionToken:'token-B'}});
  assert.equal(f.store.sessionToken,'token-B');assert.equal(f.manager.recoveryBlocked,false);
  lateResume(f.success(f.snap(6)));assert.equal(f.store.sessionToken,'token-B');
});
test('replacement cancels already scheduled retry',()=>{
  const f=fixture();f.manager.requestAuthoritativeResync();f.transport.sent[0].callback({ok:false,error:{code:'TIMEOUT'}});
  f.transport.push('session:replaced','replaced'); f.advance(12000);
  assert.equal(f.transport.sent.length,1);assert.equal(f.timers.size,0);
});
test('direct restart: passive player clears old settlement and accepts sequence 1 without ACK',()=>{
  const f=fixture();f.store.updateRoom(f.room('GAME_OVER')); f.manager.applyGameSnapshot(f.snap(120,'GAME_OVER'));
  const oldEpoch=f.store.gameEpoch;
  f.transport.push('room:state',f.room()); assert.equal(f.store.game,null);
  f.transport.push('game:snapshot',f.snap(1,'ROUND_START','match-B'));
  assert.equal(f.store.game.sequence,1);assert.equal(f.store.game.phase,'ROUND_START');assert.ok(f.store.gameEpoch>oldEpoch);
  f.transport.push('game:snapshot',f.snap(121,'GAME_OVER','match-A'));assert.equal(f.store.game.matchId,'match-B');
});
test('match identity supports restart missed while offline; same-match lower snapshots remain rejected',()=>{
  const f=fixture();f.manager.applyGameSnapshot(f.snap(80));f.manager.requestAuthoritativeResync();
  f.transport.sent[0].callback(f.success(f.snap(2,'TURN','match-B')));assert.equal(f.store.game.sequence,2);
  f.transport.push('game:snapshot',f.snap(1,'TURN','match-B'));assert.equal(f.store.game.sequence,2);
});
test('legacy server restart works without matchId through authoritative room transition',()=>{
  const f=fixture();f.store.updateRoom(f.room('GAME_OVER'));f.manager.applyGameSnapshot(f.snap(90,'GAME_OVER',''));
  f.transport.push('room:state',f.room());f.transport.push('game:snapshot',f.snap(1,'ROUND_START',''));
  assert.equal(f.store.game.phase,'ROUND_START');assert.equal(f.store.game.sequence,1);
});
test('page clears selection and audio scope even when framework coalesces new-match updates',()=>{
  const f=fixture(); const source=fs.readFileSync(path.join(root,'pages/GamePage.ets'),'utf8');
  // Execute the actual method body, excluding only the ArkUI DSL build tree.
  const body=source.slice(source.indexOf('  onGameChange('),source.indexOf('  private playPhaseSound('));
  const code=ts.transpileModule('class Page { '+body+' }; module.exports=Page;',{
    compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
  const mod={exports:{}};new Function('module',code)(mod);const page=new mod.exports();
  f.store.game=f.snap(1,'ROUND_START','match-B');f.store.gameEpoch=2;
  Object.assign(page,{store:f.store,presentationEpoch:1,selectedCardIndexes:[0],playedAudioSequence:1,lastPhase:'ROUND_START',lastRoundNumber:1,lastHandKey:'A',shareNotice:'old',showRules:true,played:0,playPhaseSound(){this.played++}});
  page.onGameChange({});assert.deepEqual(page.selectedCardIndexes,[]);assert.equal(page.played,1);
  assert.equal(page.showRules,false);assert.equal(page.shareNotice,'');
});
test('HIDDEN_BET quantities remain null',()=>{
  const f=fixture();const {parseGameSnapshot}=f.load(path.join(root,'model/Parsers.ets'));
  const g=parseGameSnapshot({discardCount:null,lastPlay:{count:null},players:[{cardCount:null,handCount:null}]});
  assert.equal(g.discardCount,null);assert.equal(g.lastPlay.count,null);assert.equal(g.players[0].cardCount,null);assert.equal(g.players[0].handCount,null);
});
test('system reduce-motion preference is followed until an explicit user override',()=>{
  const {store}=fixture();store.systemReduceMotion=true;assert.equal(store.reduceMotion,true);
  store.motionPreference='full';assert.equal(store.reduceMotion,false);
  store.motionPreference='reduced';store.systemReduceMotion=false;assert.equal(store.reduceMotion,true);
});
