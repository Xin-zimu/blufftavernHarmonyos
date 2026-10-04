// 房主探针：create + 设置模式 + ready，等所有玩家 READY 后 game:start，随后自动对局
// 用法：cd backend/apps/server && node ../../../tools/host-probe.mjs <GAME_MODE>
//   GAME_MODE: CLASSIC | ESCALATION | SHARED_REVOLVER | FREE_CHALLENGE | PARTY
// 环境变量：WS_URL（默认 ws://127.0.0.1:3001/ws）、PROBE_NICKNAME（默认 房主探针）
import { randomUUID } from 'node:crypto'
import { loadWebSocket, wsUrl } from './ws-lib.mjs'

const WebSocket = loadWebSocket()
const nickname = process.env.PROBE_NICKNAME || '房主探针'
const gameMode = process.argv[2] || 'CLASSIC'

const ws = new WebSocket(wsUrl())
const pending = new Map()
let myId = null
let roomCode = null
let lastActedSeq = -1
let started = false

function send(event, payload) {
  const msgId = randomUUID()
  return new Promise((resolve, reject) => {
    pending.set(msgId, resolve)
    ws.send(JSON.stringify({ v: 1, id: msgId, event, payload }))
    setTimeout(() => reject(new Error('timeout ' + event)), 15000)
  })
}

function maybeStart(players) {
  if (started || !roomCode) return
  const others = players.filter((p) => p.id !== myId)
  if (others.length === 0) return
  if (players.every((p) => p.status === 'READY')) {
    started = true
    send('game:start', { roomCode, requestId: randomUUID() })
      .then((a) => console.log('[HOST] game:start ack ok=' + a.ok + (a.ok ? '' : ' err=' + JSON.stringify(a.error))))
      .catch((e) => console.error('[HOST] game:start failed: ' + e.message))
  }
}

function onGameFrame(event, p) {
  const players = (p.players || []).map((pl) => `${pl.name}:${pl.handCount ?? '?'}:${pl.alive ? 'a' : 'x'}`).join(' ')
  console.log(`[HOST] ${event} seq=${p.sequence} phase=${p.phase} turn=${p.turnPlayerId} round=${p.roundNumber} target=${p.targetCard} mustC=${p.mustChallenge} hand=[${(p.hand || []).join(',')}] players=[${players}]`)
  if (myId && p.turnPlayerId === myId && p.phase === 'TURN' && p.sequence > lastActedSeq) {
    lastActedSeq = p.sequence
    if (p.mustChallenge || (p.hand || []).length === 0) {
      send('game:challenge', { roomCode, requestId: randomUUID() })
        .then((a) => console.log('[HOST] auto-challenge ack ok=' + a.ok + (a.ok ? '' : ' err=' + JSON.stringify(a.error))))
        .catch((e) => console.error('[HOST] auto-challenge failed: ' + e.message))
    } else {
      send('game:playCards', { roomCode, requestId: randomUUID(), cardIndexes: [0] })
        .then((a) => console.log('[HOST] auto-play[0] ack ok=' + a.ok + (a.ok ? '' : ' err=' + JSON.stringify(a.error))))
        .catch((e) => console.error('[HOST] auto-play failed: ' + e.message))
    }
  }
}

ws.on('open', async () => {
  try {
    const created = await send('room:create', { nickname })
    console.log('[HOST] create ack ok=' + created.ok + (created.ok ? '' : ' err=' + JSON.stringify(created.error)))
    if (!created.ok) process.exit(1)
    roomCode = created.data.room.code
    myId = created.data.playerId ?? created.data.room?.hostPlayerId
    console.log('[HOST] roomCode=' + roomCode + ' myId=' + myId)
    const upd = await send('room:updateSettings', { roomCode, maxPlayers: 8, gameMode, requestId: randomUUID() })
    console.log('[HOST] updateSettings(' + gameMode + ') ack ok=' + upd.ok + (upd.ok ? '' : ' err=' + JSON.stringify(upd.error)))
    const ready = await send('room:ready', { roomCode, ready: true, requestId: randomUUID() })
    console.log('[HOST] ready ack ok=' + ready.ok)
    console.log('[HOST] WAITING_FOR_GUEST')
  } catch (e) {
    console.error('[HOST] FAIL: ' + e.message)
    process.exit(1)
  }
})

ws.on('message', (raw) => {
  const frame = JSON.parse(raw.toString())
  if (frame.event === '@ping') { ws.send(JSON.stringify({ v: 1, event: '@pong' })); return }
  if (frame.event === '@pong') return
  if (frame.id && pending.has(frame.id)) {
    pending.get(frame.id)(frame)
    pending.delete(frame.id)
    return
  }
  const p = frame.payload ?? {}
  if (frame.event === 'game:snapshot' || frame.event === 'game:turnStarted' || frame.event === 'game:state') {
    onGameFrame(frame.event, p)
  } else if (frame.event === 'room:state') {
    const players = (p.players || []).map((pl) => `${pl.nickname}:${pl.status}`).join(' ')
    console.log(`[HOST] room:state status=${p.status} players=[${players}]`)
    if (p.status === 'LOBBY') maybeStart(p.players || [])
  } else if (frame.event === 'game:over') {
    console.log('[HOST] game:over winner=' + (p.winnerId ?? '?') + ' phase=' + p.phase)
  } else if (frame.event === 'room:kicked') {
    console.log('[HOST] room:kicked ' + JSON.stringify(p))
  } else if (frame.event === 'room:closed') {
    console.log('[HOST] room:closed')
  } else {
    console.log('[HOST] PUSH ' + frame.event + ' ' + JSON.stringify(p).slice(0, 200))
  }
})

ws.on('error', (e) => { console.error('[HOST] WS ERROR: ' + e.message) })
ws.on('close', () => { console.log('[HOST] ws closed'); process.exit(0) })
const heartbeat = setInterval(() => {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ v: 1, event: '@ping' }))
}, 10000)
setTimeout(() => { clearInterval(heartbeat); console.log('[HOST] probe timeout, exiting'); process.exit(0) }, 1800000)
