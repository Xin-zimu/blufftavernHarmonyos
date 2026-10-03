import { io, type Socket } from 'socket.io-client';
import type { ClientToServerEvents, RoomMembership, ServerToClientEvents } from '@bluff-tavern/shared';

const url = process.env.SMOKE_SERVER_URL ?? 'http://127.0.0.1:3001';
const clients: Socket<ServerToClientEvents, ClientToServerEvents>[] = [];

function connect(): Promise<Socket<ServerToClientEvents, ClientToServerEvents>> {
  const socket: Socket<ServerToClientEvents, ClientToServerEvents> = io(url, { transports: ['websocket'], forceNew: true });
  clients.push(socket);
  return new Promise((resolve, reject) => {
    socket.once('connect', () => resolve(socket));
    socket.once('connect_error', reject);
  });
}

try {
  const creator = await connect();
  const created = await new Promise<RoomMembership>((resolve, reject) => creator.emit('room:create', { nickname: '验收甲' }, (ack) => ack.ok ? resolve(ack.data) : reject(new Error(ack.error.message))));
  const guest = await connect();
  const joined = await new Promise<RoomMembership>((resolve, reject) => guest.emit('room:join', { nickname: '验收乙', roomCode: created.room.code }, (ack) => ack.ok ? resolve(ack.data) : reject(new Error(ack.error.message))));
  if (joined.room.players.length !== 2) throw new Error('Player list did not synchronize');
  console.log(JSON.stringify({ ok: true, roomCode: joined.room.code, players: joined.room.players.map((player) => player.nickname) }));
} finally {
  clients.forEach((client) => client.disconnect());
}
