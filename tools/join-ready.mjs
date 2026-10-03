// 第二玩家观察探针：加入房间、准备、监听并打印所有推送（不自动出牌，留档备用）
// 用法：cd backend/apps/server && node ../../../tools/join-ready.mjs <roomCode>
// 环境变量：WS_URL（默认 ws://127.0.0.1:3001/ws）、PROBE_NICKNAME（默认 第二玩家）
import { loadWebSocket, wsUrl } from './ws-lib.mjs'

const WebSocket = loadWebSocket()
const nickname = process.env.PROBE_NICKNAME || '第二玩家'

const roomCode = process.argv[2]
if (!roomCode) {
  console.error('usage: node join-ready.mjs <roomCode>')
  process.exit(1)
}

const ws = new WebSocket(wsUrl())
let id = 0
const pending = new Map()

function send(event, payload) {
  const msgId = `p2-${++id}`
  return new Promise((resolve, reject) => {
    pending.set(msgId, resolve)
    ws.send(JSON.stringify({ v: 1, id: msgId, event, payload }))
    setTimeout(() => reject(new Error('timeout ' + event)), 5000)
  })
}

ws.on('open', async () => {
  try {
    const join = await send('room:join', { nickname, roomCode })
    console.log('[P2] join ack ok=' + join.ok + (join.ok ? '' : ' err=' + JSON.stringify(join.error)))
    if (!join.ok) process.exit(1)
    const ready = await send('room:ready', { roomCode, ready: true, requestId: '11111111-2222-4333-8444-555555555555' })
    console.log('[P2] ready ack ok=' + ready.ok + (ready.ok ? '' : ' err=' + JSON.stringify(ready.error)))
    console.log('[P2] waiting for pushes...')
  } catch (e) {
    console.error('[P2] FAIL: ' + e.message)
    process.exit(1)
  }
})

ws.on('message', (raw) => {
  const frame = JSON.parse(raw.toString())
  if (frame.event === '@ping') {
    ws.send(JSON.stringify({ v: 1, event: '@pong' }))
    return
  }
  if (frame.id && pending.has(frame.id)) {
    pending.get(frame.id)(frame)
    pending.delete(frame.id)
    return
  }
  if (frame.event === 'room:state') {
    const players = (frame.payload.players || []).map((p) => `${p.nickname}:${p.status}`).join(', ')
    console.log(`[P2] PUSH room:state status=${frame.payload.status} players=[${players}]`)
  } else if (frame.event === 'game:snapshot') {
    const g = frame.payload
    console.log(`[P2] PUSH game:snapshot phase=${g.phase} turn=${g.turnPlayerId} round=${g.roundNumber} target=${g.targetCard}`)
  } else {
    console.log('[P2] PUSH ' + frame.event + ' ' + JSON.stringify(frame.payload || {}).slice(0, 150))
  }
})

ws.on('error', (e) => { console.error('[P2] WS ERROR: ' + e.message) })
ws.on('close', () => { console.log('[P2] ws closed'); process.exit(0) })
const heartbeat = setInterval(() => {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ v: 1, event: '@ping' }))
  }
}, 10000)
setTimeout(() => { clearInterval(heartbeat); console.log('[P2] probe timeout, exiting'); process.exit(0) }, 240000)
