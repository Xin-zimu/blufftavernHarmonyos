// 验收3 probe: connects as a SECOND connection and resumes the app's session token.
// Logs every frame. Keeps the session until killed.
import { randomUUID } from 'node:crypto';
import { loadWebSocket, wsUrl } from './ws-lib.mjs';

const WebSocket = loadWebSocket();
const TOKEN = process.argv[2];
const URL = process.argv[3] ?? wsUrl();
if (!TOKEN) {
  console.error('usage: node resume-probe.mjs <sessionToken> [url]');
  process.exit(1);
}

const ws = new WebSocket(URL);
let seq = 0;
const log = (msg) => console.log(`[RP] ${msg}`);

ws.on('open', () => {
  log('connected');
  ws.send(JSON.stringify({ v: 1, id: `c-${++seq}`, event: 'session:resume', payload: { sessionToken: TOKEN } }));
  setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ v: 1, event: '@ping' }));
  }, 10000);
});
ws.on('message', (data) => {
  const raw = String(data);
  let frame;
  try {
    frame = JSON.parse(raw);
  } catch {
    log('bad frame: ' + raw.slice(0, 120));
    return;
  }
  if (frame.event === '@pong') return;
  if (frame.event) {
    log(`PUSH ${frame.event} ${JSON.stringify(frame.payload).slice(0, 200)}`);
  } else {
    log(`ACK id=${frame.id} ok=${frame.ok} ${frame.ok ? '' : JSON.stringify(frame.error)}`);
    if (frame.ok) {
      const room = frame.data?.room;
      if (room) log(`resumed room=${room.code} status=${room.status} players=[${room.players.map((p) => `${p.nickname}:${p.status}`).join(' ')}]`);
    }
  }
});
ws.on('close', (code, reason) => log(`closed code=${code} reason=${reason}`));
ws.on('error', (err) => log(`error ${err.message}`));
setTimeout(() => {
  log('30min timeout, exiting');
  process.exit(0);
}, 1800000).unref();
