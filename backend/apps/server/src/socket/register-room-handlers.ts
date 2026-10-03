// Socket.IO transport adapter: bridges socket.io sockets onto the shared
// CommandDispatcher / ConnectionRegistry. All business handling lives in the
// dispatcher; this file only translates transport events.

import type { Server, Socket } from 'socket.io';
import type { ClientToServerEvents, InterServerEvents, ServerToClientEvents, SocketData } from '@bluff-tavern/shared';
import type { CommandDispatcher } from '../realtime/command-dispatcher.js';
import type { ClientConnection, ConnectionRegistry } from '../realtime/connection-registry.js';

type GameServer = Server<ClientToServerEvents, ServerToClientEvents, InterServerEvents, SocketData>;
type GameSocket = Socket<ClientToServerEvents, ServerToClientEvents, InterServerEvents, SocketData>;

export function registerRoomHandlers(_io: GameServer, socket: GameSocket, dispatcher: CommandDispatcher, registry: ConnectionRegistry): void {
  const connectionId = `socketio:${socket.id}`;
  const emitGeneric = socket.emit.bind(socket) as unknown as (event: string, ...args: unknown[]) => void;
  const connection: ClientConnection = {
    id: connectionId,
    transport: 'socketio',
    send: (event: string, payload: unknown) => {
      emitGeneric(event, payload);
    },
    close: () => {
      socket.disconnect(true);
    },
  };
  registry.register(connection);

  socket.onAny((event: string, ...args: unknown[]) => {
    if (!dispatcher.isBusinessEvent(event)) return;
    const payload = args[0];
    const ack = args[1];
    if (typeof ack !== 'function') return; // Business events always carry an ack callback.
    dispatcher.handleCommand(
      {
        connectionId,
        sendAck: (result) => {
          (ack as (value: unknown) => void)(result);
        },
        close: () => {
          connection.close();
        },
      },
      event,
      payload,
    );
  });

  socket.on('disconnect', () => {
    registry.unregister(connectionId);
    dispatcher.handleDisconnect(connectionId);
  });
}
