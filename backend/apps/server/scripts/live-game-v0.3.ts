import { randomUUID } from 'node:crypto';
import { io, type Socket } from 'socket.io-client';
import type { Ack, ClientToServerEvents, GameView, RoomMembership, RoomView, ServerToClientEvents } from '@bluff-tavern/shared';

const url = process.env.SMOKE_SERVER_URL ?? 'http://127.0.0.1:5173';
const clients: Socket<ServerToClientEvents, ClientToServerEvents>[] = [];
const connect = () => new Promise<Socket<ServerToClientEvents, ClientToServerEvents>>((resolve, reject) => { const socket = io(url, { transports: ['websocket'], forceNew: true }); clients.push(socket); socket.once('connect', () => resolve(socket)); socket.once('connect_error', reject); });
const request = <T>(socket: Socket<ServerToClientEvents, ClientToServerEvents>, event: 'room:create' | 'room:join' | 'room:ready' | 'game:start' | 'game:playCards', payload: object) => new Promise<Ack<T>>((resolve) => socket.emit(event, payload as never, resolve as never));

try {
  const host = await connect(); const made = await request<RoomMembership>(host, 'room:create', { nickname: '甲' }); if (!made.ok) throw new Error(made.error.message);
  const guest = await connect(); const joined = await request<RoomMembership>(guest, 'room:join', { nickname: '乙', roomCode: made.data.room.code }); if (!joined.ok) throw new Error(joined.error.message);
  await Promise.all([host, guest].map((socket) => request<RoomView>(socket, 'room:ready', { roomCode: made.data.room.code, ready: true, requestId: randomUUID() })));
  const started = await request<GameView>(host, 'game:start', { roomCode: made.data.room.code, requestId: randomUUID() }); if (!started.ok) throw new Error(started.error.message);
  const turnSocket = started.data.turnPlayerId === made.data.playerId ? host : guest;
  const played = await request<GameView>(turnSocket, 'game:playCards', { roomCode: made.data.room.code, cardIndexes: [0], requestId: randomUUID() }); if (!played.ok) throw new Error(played.error.message);
  console.log(JSON.stringify({ ok: true, roomCode: made.data.room.code, target: started.data.targetCard, discardCount: played.data.discardCount, ownHandIsPrivate: played.data.hand.length > 0 }));
} finally { clients.forEach((client) => client.disconnect()); }
