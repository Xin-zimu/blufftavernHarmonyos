// Unified connection registry shared by the Socket.IO and raw-WS transports.
// Every realtime connection (either transport) is registered here with a
// globally unique id (`socketio:<id>` / `ws:<uuid>`), its bound identity and
// its room subscriptions. Publishing and connection management address
// connections exclusively through these unified ids.

export type TransportKind = 'socketio' | 'ws';

export interface ClientConnection {
  readonly id: string;
  readonly transport: TransportKind;
  send(event: string, payload: unknown): void;
  close(): void;
}

export interface ConnectionIdentity {
  playerId?: string;
  roomCode?: string;
}

interface RegistryEntry {
  connection: ClientConnection;
  identity: ConnectionIdentity;
  rooms: Set<string>;
}

export class ConnectionRegistry {
  private readonly entries = new Map<string, RegistryEntry>();
  private readonly roomMembers = new Map<string, Set<string>>();

  register(connection: ClientConnection): void {
    if (this.entries.has(connection.id)) return;
    this.entries.set(connection.id, { connection, identity: {}, rooms: new Set() });
  }

  unregister(connectionId: string): void {
    const entry = this.entries.get(connectionId);
    if (!entry) return;
    for (const roomCode of entry.rooms) this.removeFromRoom(roomCode, connectionId);
    this.entries.delete(connectionId);
  }

  has(connectionId: string): boolean {
    return this.entries.has(connectionId);
  }

  get(connectionId: string): ClientConnection | null {
    return this.entries.get(connectionId)?.connection ?? null;
  }

  getIdentity(connectionId: string): ConnectionIdentity {
    return this.entries.get(connectionId)?.identity ?? {};
  }

  setIdentity(connectionId: string, identity: ConnectionIdentity): void {
    const entry = this.entries.get(connectionId);
    if (entry) entry.identity = identity;
  }

  clearIdentity(connectionId: string): void {
    const entry = this.entries.get(connectionId);
    if (entry) entry.identity = {};
  }

  joinRoom(connectionId: string, roomCode: string): void {
    const entry = this.entries.get(connectionId);
    if (!entry) return;
    entry.rooms.add(roomCode);
    let members = this.roomMembers.get(roomCode);
    if (!members) {
      members = new Set();
      this.roomMembers.set(roomCode, members);
    }
    members.add(connectionId);
  }

  leaveRoom(connectionId: string, roomCode: string): void {
    const entry = this.entries.get(connectionId);
    if (!entry) return;
    entry.rooms.delete(roomCode);
    this.removeFromRoom(roomCode, connectionId);
  }

  leaveAllRooms(connectionId: string): void {
    const entry = this.entries.get(connectionId);
    if (!entry) return;
    for (const roomCode of [...entry.rooms]) this.leaveRoom(connectionId, roomCode);
  }

  roomConnectionIds(roomCode: string): string[] {
    return [...(this.roomMembers.get(roomCode) ?? [])];
  }

  private removeFromRoom(roomCode: string, connectionId: string): void {
    const members = this.roomMembers.get(roomCode);
    if (!members) return;
    members.delete(connectionId);
    if (members.size === 0) this.roomMembers.delete(roomCode);
  }
}
