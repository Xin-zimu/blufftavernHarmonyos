import { randomUUID } from 'node:crypto';
import { io, type Socket } from 'socket.io-client';
import type { Ack, ClientToServerEvents, GameView, RoomMembership, RoomView, ServerToClientEvents } from '@bluff-tavern/shared';

const url = 'http://127.0.0.1:5173';
type GameSocket = Socket<ServerToClientEvents, ClientToServerEvents>;
const make = () => new Promise<GameSocket>((resolve, reject) => { const socket: GameSocket = io(url, { transports: ['websocket'], forceNew: true }); socket.once('connect', () => resolve(socket)); socket.once('connect_error', reject); });
const request = <T>(socket: GameSocket, event: 'room:create' | 'room:join' | 'room:ready' | 'game:start' | 'game:playCards' | 'game:challenge', payload: object) => new Promise<Ack<T>>((resolve) => socket.emit(event, payload as never, resolve as never));
const sockets: GameSocket[] = [];
try {
  const a = await make(); sockets.push(a); const made = await request<RoomMembership>(a, 'room:create', { nickname: '甲' }); if (!made.ok) throw new Error(made.error.message);
  const b = await make(); sockets.push(b); const joined = await request<RoomMembership>(b, 'room:join', { nickname: '乙', roomCode: made.data.room.code }); if (!joined.ok) throw new Error(joined.error.message);
  await Promise.all([a, b].map((socket) => request<RoomView>(socket, 'room:ready', { roomCode: made.data.room.code, ready: true, requestId: randomUUID() })));
  const started = await request<GameView>(a, 'game:start', { roomCode: made.data.room.code, requestId: randomUUID() }); if (!started.ok) throw new Error(started.error.message);
  const player = started.data.turnPlayerId === made.data.playerId ? a : b; const challenger = player === a ? b : a;
  const play = await request<GameView>(player, 'game:playCards', { roomCode: made.data.room.code, cardIndexes: [0], requestId: randomUUID() }); if (!play.ok) throw new Error(play.error.message);
  const challenge = await request<GameView>(challenger, 'game:challenge', { roomCode: made.data.room.code, requestId: randomUUID() }); if (!challenge.ok) throw new Error(challenge.error.message);
  console.log(JSON.stringify({ ok: true, phase: challenge.data.phase, result: challenge.data.challengeResult }));
} finally { sockets.forEach((socket) => socket.disconnect()); }
