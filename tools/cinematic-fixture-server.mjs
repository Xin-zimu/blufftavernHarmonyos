// Local deterministic acceptance transport. No production server or cloud writes.
// Run separately on port 3015; use only with the test HAP described in the report.
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../backend/apps/server/package.json', import.meta.url));
const { WebSocketServer } = require('ws');
const port = Number(process.env.CINEMATIC_PORT || 3015);
const logs = [];
let sequence = 0, match = 0, timers = [], scenario = { cards: ['A','A','JOKER'], bluff: false, hits: [false] };
export const room = {
  id: 'cinematic-local', code: 'CINE72', hostPlayerId: 'p1', status: 'PLAYING', maxPlayers: 2,
  settings: { maxPlayers: 2, gameMode: 'CLASSIC', turnDurationSeconds: 15, eventEnabled: false, bulletCount: null,
    v7: { itemsEnabled: false, tavernEventsEnabled: false, characterAbilitiesEnabled: false } },
  players: ['p1','p2'].map((id,i) => ({ id, nickname: i ? '质疑者' : '出牌者', status: 'PLAYING', joinedAt: 0, isConnected: true, characterId: null })), createdAt: 0
};
let game;
function makeGame(phase, duration, shot = 0, elapsed = 0) {
  const now = Date.now(), published = phase === 'PUNISHMENT_RESULT' || phase === 'ROUND_END';
  const revealed = !['CHALLENGE_CALLOUT','TURN','ROUND_START'].includes(phase);
  const hit = scenario.hits[shot] ?? false;
  return {
    matchId: `fixture-${match}`, sequence: ++sequence, serverNow: now, phase, phaseStartedAt: now-elapsed,
    phaseEndsAt: duration === null ? null : now-elapsed+duration,
    gameMode: scenario.hits.length > 1 ? 'PARTY' : 'CLASSIC', turnDurationSeconds: 15, roundNumber: 1,
    targetRank: 'A', targetCard: 'A', turnPlayerId: phase === 'TURN' ? 'p1' : null,
    mustChallenge: false, minimumPlayCount: 1, maximumPlayCount: 3, turnDirection: 'CLOCKWISE',
    players: room.players.map((p,i) => ({ playerId: p.id, name: p.nickname, seatIndex: i, connected: true, alive: true, handCount: 5, cardCount: 5 })),
    hand: ['A','K','Q','JOKER','A'], discardCount: scenario.cards.length,
    lastPlay: { playerId: 'p1', count: scenario.cards.length, claimedRank: 'A' },
    challenge: phase === 'TURN' || phase === 'ROUND_START' ? null : { challengerId: 'p2', challengedId: 'p1', revealedCards: revealed ? scenario.cards : null,
      wasBluff: revealed && phase !== 'REVEAL' ? scenario.bluff : null, punishedPlayerId: revealed && phase !== 'REVEAL' ? (scenario.bluff ? 'p1' : 'p2') : null },
    punishment: published ? { punishedPlayerId: scenario.bluff ? 'p1' : 'p2', playerId: scenario.bluff ? 'p1' : 'p2',
      chamber: shot + 2, hit, eliminatedPlayerId: hit ? (scenario.bluff ? 'p1' : 'p2') : null, shotNumber: shot+1, totalShots: hit ? shot+1 : scenario.hits.length } : null,
    winner: null, winnerId: null, summary: null, freeChallenge: null, sharedRevolver: null, alivePlayerIds: ['p1','p2'],
    tavernEvent: scenario.hits.length > 1 ? { type: 'DOUBLE_DANGER', title: '双倍危机', description: '最多连续开两枪', category: 'PUNISHMENT', roundNumber: 1, turnDurationSeconds: null, intensity: 'HIGH' } : null,
    partyEventHistory: [], items: [], itemEffect: null, abilityEffect: null, challengeResult: null
  };
}
function publish(phase, duration, shot=0, elapsed=0) {
  game = makeGame(phase,duration,shot,elapsed);
  logs.push({phase,shot,at:Date.now(),startedAt:game.phaseStartedAt,endsAt:game.phaseEndsAt,matchId:game.matchId});
  for(const ws of sockets.clients) if(ws.readyState===1) ws.send(JSON.stringify({v:1,event:'game:snapshot',payload:game}));
  console.log(JSON.stringify(logs.at(-1)));
}
function run(spec) {
  timers.forEach(clearTimeout); timers=[]; scenario={cards:['A','A','JOKER'],bluff:false,hits:[false],...spec}; match++;
  const steps = [['CHALLENGE_CALLOUT',1800,0],['REVEAL',500+scenario.cards.length*750+1000,0],['VERDICT',1300,0],['PUNISHMENT_INTRO',1050,0]];
  scenario.hits.forEach((hit,i)=>steps.push(['PUNISHMENT_TRIGGER',700+(scenario.hits.length>1?450:0),i],['PUNISHMENT_RESULT',hit?1650:1250,i]));
  steps.push(['ROUND_END',900,scenario.hits.length-1],['ROUND_START',2700,0],['TURN',null,0]);
  if(spec.phase) { publish(spec.phase,spec.duration ?? 500+scenario.cards.length*750+1000,spec.shot||0,spec.elapsed||0); return; }
  let offset=Number(spec.delay ?? 1000);
  for(const [phase,duration,shot] of steps) { timers.push(setTimeout(()=>publish(phase,duration,shot),offset)); offset+=duration||0; }
  return offset;
}
const server=createServer(async(req,res)=>{
  res.setHeader('Access-Control-Allow-Origin','*');res.setHeader('Access-Control-Allow-Headers','Content-Type');
  if(req.method==='OPTIONS'){res.end();return;}
  let body='';for await(const chunk of req)body+=chunk;
  const url=new URL(req.url,'http://localhost');
  res.setHeader('Content-Type','application/json');
  if(url.pathname==='/run') {const duration=run(JSON.parse(body||'{}'));res.end(JSON.stringify({ok:true,duration}));return;}
  if(url.pathname==='/duplicate') { game={...game,sequence:++sequence,serverNow:Date.now()};for(const ws of sockets.clients)ws.send(JSON.stringify({v:1,event:'game:snapshot',payload:game}));res.end('{"ok":true}');return; }
  if(url.pathname==='/disconnect') {for(const ws of sockets.clients)ws.terminate();res.end('{"ok":true}');return;}
  if(url.pathname==='/logs'){res.end(JSON.stringify(logs));return;}
  res.end(JSON.stringify({room,game:{...game,serverNow:Date.now()},clients:sockets.clients.size}));
});
const sockets=new WebSocketServer({server,path:'/ws'});
sockets.on('connection',ws=>{
  console.log('fixture device connected');
  ws.on('message',raw=>{
    const frame=JSON.parse(raw.toString());
    if(frame.event==='@ping'){ws.send(JSON.stringify({v:1,event:'@pong'}));return;}
    if(!frame.id)return;
    const data={room,playerId:'p1',sessionToken:'LOCAL-CINEMATIC-FIXTURE',game:{...game,serverNow:Date.now()}};
    ws.send(JSON.stringify({v:1,id:frame.id,ok:true,data}));
    setTimeout(()=>ws.readyState===1&&ws.send(JSON.stringify({v:1,event:'game:snapshot',payload:{...game,serverNow:Date.now()}})),150);
  });
});
game=makeGame('TURN',null);
server.listen(port,'0.0.0.0',()=>console.log(`Local cinematic fixtures http://127.0.0.1:${port}`));
