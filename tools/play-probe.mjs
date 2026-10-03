// 第二玩家自动对局探针：join+ready，轮到自己时自动出牌（mustChallenge/手牌空时自动质疑）
// 用法：cd backend/apps/server && node ../../../tools/play-probe.mjs <roomCode>
// 环境变量：WS_URL（默认 ws://127.0.0.1:3001/ws）、PROBE_NICKNAME（默认 第二玩家）
import { randomUUID } from 'node:crypto'
import { loadWebSocket, wsUrl } from './ws-lib.mjs'

const WebSocket = loadWebSocket()
const nickname = process.env.PROBE_NICKNAME || '第二玩家'

const roomCode = process.argv[2]
if (!roomCode) {
  console.error('usage: node play-probe.mjs <roomCode>')
  process.exit(1)
}

const ws = new WebSocket(wsUrl())
const pending = new Map()
let myId = null
let lastActedSeq = -1

function send(event, payload) {
  const msgId = randomUUID()
  return new Promise((resolve, reject) => {
    pending.set(msgId, resolve)
    ws.send(JSON.stringify({ v: 1, id: msgId, event, payload }))
    setTimeout(() => reject(new Error('timeout ' + event)), 10000)
  })
}

function onGameFrame(event, p) {
  const players = (p.players || []).map((pl) => `${pl.name}:${pl.handCount ?? '?'}:${pl.alive ? 'a' : 'x'}`).join(' ')
  console.log(`[P2] ${event} seq=${p.sequence} phase=${p.phase} turn=${p.turnPlayerId} round=${p.roundNumber} target=${p.targetCard} mustC=${p.mustChallenge} hand=[${(p.hand || []).join(',')}] players=[${players}]`)
  if (myId && p.turnPlayerId === myId && p.phase === 'TURN' && p.sequence > lastActedSeq) {
    lastActedSeq = p.sequence
    if (p.mustChallenge || (p.hand || []).length === 0) {
      send('game:challenge', { roomCode, requestId: randomUUID() })
        .then((a) => console.log('[P2] auto-challenge ack ok=' + a.ok + (a.ok ? '' : ' err=' + JSON.stringify(a.error))))
        .catch((e) => console.error('[P2] auto-challenge failed: ' + e.message))
    } else {
      send('game:playCards', { roomCode, requestId: randomUUID(), cardIndexes: [0] })
        .then((a) => console.log('[P2] auto-play[0] ack ok=' + a.ok + (a.ok ? '' : ' err=' + JSON.stringify(a.error))))
        .catch((e) => console.error('[P2] auto-play failed: ' + e.message))
    }
  }
}

ws.on('open', async () => {
  try {
    const join = await send('room:join', { nickname, roomCode })
    console.log('[P2] join ack ok=' + join.ok + (join.ok ? '' : ' err=' + JSON.stringify(join.error)))
    if (!join.ok) process.exit(1)
    myId = join.data.playerId
    console.log('[P2] myId=' + myId)
    const ready = await send('room:ready', { roomCode, ready: true, requestId: randomUUID() })
    console.log('[P2] ready ack ok=' + ready.ok)
  } catch (e) {
    console.error('[P2] FAIL: ' + e.message)
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
    console.log(`[P2] room:state status=${p.status} players=[${players}]`)
  } else if (frame.event === 'game:over') {
    console.log('[P2] game:over winner=' + (p.winnerId ?? '?') + ' phase=' + p.phase)
  } else if (frame.event === 'room:kicked') {
    console.log('[P2] room:kicked ' + JSON.stringify(p))
  } else if (frame.event === 'room:closed') {
    console.log('[P2] room:closed')
  } else {
    console.log('[P2] PUSH ' + frame.event + ' ' + JSON.stringify(p).slice(0, 200))
  }
})

ws.on('error', (e) => { console.error('[P2] WS ERROR: ' + e.message) })
ws.on('close', () => { console.log('[P2] ws closed'); process.exit(0) })
const heartbeat = setInterval(() => {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ v: 1, event: '@ping' }))
}, 10000)
setTimeout(() => { clearInterval(heartbeat); console.log('[P2] probe timeout, exiting'); process.exit(0) }, 1800000)
