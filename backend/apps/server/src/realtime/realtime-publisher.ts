// Cross-transport publishing: unicast to a connection, broadcast to a room,
// and connection teardown. All addressing goes through unified connection ids.

import type { ConnectionRegistry } from './connection-registry.js';

export class RealtimePublisher {
  constructor(private readonly registry: ConnectionRegistry) {}

  sendToConnection(connectionId: string, event: string, payload: unknown): void {
    const connection = this.registry.get(connectionId);
    if (connection) connection.send(event, payload);
  }

  broadcastToRoom(roomCode: string, event: string, payload: unknown): void {
    for (const connectionId of this.registry.roomConnectionIds(roomCode)) {
      this.sendToConnection(connectionId, event, payload);
    }
  }

  closeConnection(connectionId: string): void {
    const connection = this.registry.get(connectionId);
    if (connection) connection.close();
  }
}
