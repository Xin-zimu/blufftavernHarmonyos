import { randomUUID } from 'node:crypto';
import { io, type Socket } from 'socket.io-client';
import type { Ack, ClientToServerEvents, GameView, RoomMembership, RoomView, ServerToClientEvents } from '@bluff-tavern/shared';

const url = process.env.SMOKE_SERVER_URL ?? 'http://127.0.0.1:5173';
type GameSocket = Socket<ServerToClientEvents, ClientToServerEvents>;
const clients: GameSocket[] = [];
const connect = () => new Promise<GameSocket>((resolve, reject) => {
  const socket: GameSocket = io(url, { transports: ['websocket'], forceNew: true });
  clients.push(socket);
  socket.once('connect', () => resolve(socket));
  socket.once('connect_error', reject);
});
const request = <T>(socket: GameSocket, event: 'room:create' | 'room:join' | 'room:ready' | 'game:start' | 'session:resume', payload: object) => new Promise<Ack<T>>((resolve) => socket.emit(event, payload as never, resolve as never));

try {
  const host = await connect();
  const made = await request<RoomMembership>(host, 'room:create', { nickname: '断线房主' });
  if (!made.ok) throw new Error(made.error.message);
  const guest = await connect();
  const joined = await request<RoomMembership>(guest, 'room:join', { nickname: '断线玩家', roomCode: made.data.room.code });
  if (!joined.ok) throw new Error(joined.error.message);
  await Promise.all([host, guest].map((client) => request<RoomView>(client, 'room:ready', { roomCode: made.data.room.code, ready: true, requestId: randomUUID() })));
  const started = await request<GameView>(host, 'game:start', { roomCode: made.data.room.code, requestId: randomUUID() });
  if (!started.ok) throw new Error(started.error.message);
  guest.disconnect();
  await new Promise((resolve) => setTimeout(resolve, 80));
  const reconnect = await connect();
  const resumed = await request<RoomMembership>(reconnect, 'session:resume', { sessionToken: joined.data.sessionToken });
  if (!resumed.ok) throw new Error(resumed.error.message);
  if (resumed.data.playerId !== joined.data.playerId || !resumed.data.room.players.find((player) => player.id === joined.data.playerId)?.isConnected) throw new Error('Session resume did not restore the original seat');
  console.log(JSON.stringify({ ok: true, roomCode: made.data.room.code, restoredPlayerId: resumed.data.playerId, phase: started.data.phase }));
} finally {
  clients.forEach((client) => client.disconnect());
}
