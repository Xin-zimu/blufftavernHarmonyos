import { randomUUID } from 'node:crypto';
import { io, type Socket } from 'socket.io-client';
import type { Ack, ClientToServerEvents, RoomMembership, RoomView, ServerToClientEvents } from '@bluff-tavern/shared';

const url = process.env.SMOKE_SERVER_URL ?? 'http://127.0.0.1:5173';
const clients: Socket<ServerToClientEvents, ClientToServerEvents>[] = [];

function connect(): Promise<Socket<ServerToClientEvents, ClientToServerEvents>> {
  const socket: Socket<ServerToClientEvents, ClientToServerEvents> = io(url, { transports: ['websocket'], forceNew: true });
  clients.push(socket);
  return new Promise((resolve, reject) => { socket.once('connect', () => resolve(socket)); socket.once('connect_error', reject); });
}

function request<T>(socket: Socket<ServerToClientEvents, ClientToServerEvents>, event: 'room:create' | 'room:join' | 'room:ready' | 'room:updateSettings' | 'room:kick', payload: object): Promise<Ack<T>> {
  return new Promise((resolve) => socket.emit(event, payload as never, resolve as never));
}

try {
  const host = await connect();
  const created = await request<RoomMembership>(host, 'room:create', { nickname: '房主' });
  if (!created.ok) throw new Error(created.error.message);
  const guest = await connect();
  const joined = await request<RoomMembership>(guest, 'room:join', { nickname: '客人', roomCode: created.data.room.code });
  if (!joined.ok) throw new Error(joined.error.message);
  const settings = await request<RoomView>(host, 'room:updateSettings', { roomCode: created.data.room.code, maxPlayers: 4, requestId: randomUUID() });
  const ready = await request<RoomView>(guest, 'room:ready', { roomCode: created.data.room.code, ready: true, requestId: randomUUID() });
  const kicked = new Promise<string>((resolve) => guest.once('room:kicked', resolve));
  const kick = await request<RoomView>(host, 'room:kick', { roomCode: created.data.room.code, targetPlayerId: joined.data.playerId, requestId: randomUUID() });
  if (!settings.ok || !ready.ok || !kick.ok) throw new Error('V0.2 room command failed');
  console.log(JSON.stringify({ ok: await kicked, roomCode: created.data.room.code, maxPlayers: settings.data.settings.maxPlayers, remainingPlayers: kick.data.players.length }));
} finally {
  clients.forEach((client) => client.disconnect());
}
