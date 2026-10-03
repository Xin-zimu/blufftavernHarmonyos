// 房主探针：创建房间，等待玩家加入后 2.5s 将其踢出
// 用法：cd backend/apps/server && node ../../../tools/kick-host.mjs
// 环境变量：WS_URL（默认 ws://127.0.0.1:3001/ws）、PROBE_NICKNAME（默认 房主探针）
import { randomUUID } from 'node:crypto'
import { loadWebSocket, wsUrl } from './ws-lib.mjs'

const WebSocket = loadWebSocket()
const nickname = process.env.PROBE_NICKNAME || '房主探针'

const ws = new WebSocket(wsUrl())
const pending = new Map()
let myId = null
let roomCode = null

function send(event, payload) {
  const msgId = randomUUID()
  return new Promise((resolve, reject) => {
    pending.set(msgId, resolve)
    ws.send(JSON.stringify({ v: 1, id: msgId, event, payload }))
    setTimeout(() => reject(new Error('timeout ' + event)), 10000)
  })
}

ws.on('open', async () => {
  try {
    const create = await send('room:create', { nickname })
    if (!create.ok) { console.log('[H] create failed: ' + JSON.stringify(create.error)); process.exit(1) }
    myId = create.data.playerId
    roomCode = create.data.room.code
    console.log('[H] ROOM_CODE=' + roomCode)
  } catch (e) { console.error('[H] FAIL: ' + e.message); process.exit(1) }
})

ws.on('message', (raw) => {
  const frame = JSON.parse(raw.toString())
  if (frame.event === '@ping') { ws.send(JSON.stringify({ v: 1, event: '@pong' })); return }
  if (frame.id && pending.has(frame.id)) { pending.get(frame.id)(frame); pending.delete(frame.id); return }
  const p = frame.payload ?? {}
  if (frame.event === 'room:playerJoined' && p.player && p.player.id !== myId) {
    console.log('[H] player joined: ' + p.player.nickname + ' id=' + p.player.id)
    setTimeout(async () => {
      try {
        const ack = await send('room:kick', { roomCode, targetPlayerId: p.player.id, requestId: randomUUID() })
        console.log('[H] kick ack ok=' + ack.ok + (ack.ok ? '' : ' err=' + JSON.stringify(ack.error)))
        console.log('[H] KICK_SENT')
        setTimeout(() => process.exit(0), 3000)
      } catch (e) { console.error('[H] kick failed: ' + e.message) }
    }, 2500)
  } else if (frame.event === 'room:state') {
    console.log('[H] room:state players=' + (p.players || []).length + ' status=' + p.status)
  } else if (frame.event === 'room:playerLeft') {
    console.log('[H] room:playerLeft')
  }
})

ws.on('error', (e) => console.error('[H] WS ERROR: ' + e.message))
ws.on('close', () => process.exit(0))
setInterval(() => { if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ v: 1, event: '@ping' })) }, 10000)
setTimeout(() => { console.log('[H] timeout'); process.exit(0) }, 300000)
