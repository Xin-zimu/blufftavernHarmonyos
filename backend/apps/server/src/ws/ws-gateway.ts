// Raw WebSocket gateway mounted at /ws on the existing HTTP server.
// Wire protocol (all frames are JSON):
//   client -> server business request: { v: 1, id: "c-1", event: "room:create", payload: {...} }
//   server -> client ack:             { v: 1, id: "c-1", ok: true, data: {...} }
//                                      { v: 1, id: "c-1", ok: false, error: { code, message } }
//   server -> client push:            { v: 1, event: "game:snapshot", payload: {...} }
//   heartbeat:                        { v: 1, event: "@ping" } / { v: 1, event: "@pong" }
// The "@" prefix is reserved for system frames and never reaches the business
// dispatcher. Clients may only send business requests and @ping; ack- or
// push-shaped client frames are protocol violations and close the connection.

import { randomUUID } from 'node:crypto';
import type { Server as HttpServer } from 'node:http';
import type { Server as HttpsServer } from 'node:https';
import { WebSocketServer, type WebSocket } from 'ws';
import type { CommandDispatcher } from '../realtime/command-dispatcher.js';
import type { ClientConnection, ConnectionRegistry } from '../realtime/connection-registry.js';

export interface WsGatewayLogger {
  info: (data: object) => void;
  error: (data: object) => void;
  warn: (data: object) => void;
}

export interface WsGatewayOptions {
  path?: string;
  idleTimeoutMs?: number;
  sweepIntervalMs?: number;
}

interface IdleTracker {
  socket: WebSocket;
  lastFrameAt: number;
}

const PROTOCOL_VERSION = 1;
const DEFAULT_IDLE_TIMEOUT_MS = 45_000;
const DEFAULT_SWEEP_INTERVAL_MS = 5_000;

interface Envelope {
  v?: unknown;
  id?: unknown;
  event?: unknown;
  payload?: unknown;
  ok?: unknown;
}

export class WebSocketGateway {
  private readonly wss: WebSocketServer;
  private readonly idle = new Map<string, IdleTracker>();
  private readonly sweepTimer: ReturnType<typeof setInterval>;
  private readonly idleTimeoutMs: number;
  private readonly path: string;
  private closed = false;

  constructor(
    server: HttpServer | HttpsServer,
    private readonly dispatcher: CommandDispatcher,
    private readonly registry: ConnectionRegistry,
    private readonly logger: WsGatewayLogger,
    options: WsGatewayOptions = {},
  ) {
    this.idleTimeoutMs = options.idleTimeoutMs ?? DEFAULT_IDLE_TIMEOUT_MS;
    this.path = options.path ?? '/ws';
    // noServer mode: route upgrades manually so the socket.io (engine.io)
    // listener on the same HTTP server keeps handling /socket.io/ upgrades.
    this.wss = new WebSocketServer({ noServer: true });
    this.wss.on('connection', (socket) => this.onConnection(socket));
    server.on('upgrade', (request, socket, head) => {
      if (this.closed) return;
      let pathname = '';
      try {
        pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
      } catch {
        return;
      }
      if (pathname !== this.path) return;
      this.wss.handleUpgrade(request, socket, head, (client) => {
        this.wss.emit('connection', client, request);
      });
    });
    this.sweepTimer = setInterval(
      () => this.sweep(),
      options.sweepIntervalMs ?? Math.min(DEFAULT_SWEEP_INTERVAL_MS, Math.max(50, Math.floor(this.idleTimeoutMs / 3))),
    );
    this.sweepTimer.unref?.();
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    clearInterval(this.sweepTimer);
    for (const tracker of this.idle.values()) {
      try {
        tracker.socket.close(1001, 'server shutting down');
      } catch {
        // Socket already gone.
      }
    }
    this.idle.clear();
    this.wss.close();
  }

  private onConnection(socket: WebSocket): void {
    const connectionId = `ws:${randomUUID()}`;
    const connection: ClientConnection = {
      id: connectionId,
      transport: 'ws',
      send: (event: string, payload: unknown) => {
        this.sendRaw(socket, { v: PROTOCOL_VERSION, event, payload: payload === undefined ? null : payload });
      },
      close: () => {
        try {
          socket.close(1000, 'closed by server');
        } catch {
          // Socket already gone.
        }
      },
      terminate: () => {
        try {
          socket.terminate();
        } catch {
          // Socket already gone.
        }
      },
    };
    this.registry.register(connection);
    this.idle.set(connectionId, { socket, lastFrameAt: Date.now() });
    socket.on('message', (data: unknown) => {
      try {
        this.onMessage(connectionId, socket, typeof data === 'string' ? data : String(data));
      } catch (error) {
        this.logger.error({ event: 'ws_message_failed', connectionId, error });
      }
    });
    socket.on('close', () => this.onClose(connectionId));
    socket.on('error', (error: Error) => {
      this.logger.warn({ event: 'ws_socket_error', connectionId, message: error.message });
    });
  }

  private onMessage(connectionId: string, socket: WebSocket, raw: string): void {
    let frame: Envelope;
    try {
      frame = JSON.parse(raw) as Envelope;
    } catch {
      this.protocolViolation(socket, 'invalid json');
      return;
    }
    if (frame === null || typeof frame !== 'object' || Array.isArray(frame)) {
      this.protocolViolation(socket, 'frame must be an object');
      return;
    }
    if ('ok' in frame) {
      // Clients may not send ack- or push-shaped frames.
      this.protocolViolation(socket, 'clients must not send ack frames');
      return;
    }
    if (frame.v !== PROTOCOL_VERSION) {
      this.sendAckError(socket, idOf(frame), 'INVALID_ENVELOPE', '协议版本不受支持');
      return;
    }
    const event = frame.event;
    if (typeof event !== 'string' || event.length === 0) {
      this.protocolViolation(socket, 'missing event');
      return;
    }
    if (event.startsWith('@')) {
      if (event === '@ping') {
        this.markFrame(connectionId);
        this.sendRaw(socket, { v: PROTOCOL_VERSION, event: '@pong' });
        return;
      }
      if (event === '@pong') {
        this.markFrame(connectionId);
        return;
      }
      this.protocolViolation(socket, `unknown system frame: ${event}`);
      return;
    }
    const id = frame.id;
    if (typeof id !== 'string' || id.length === 0) {
      this.protocolViolation(socket, 'business request requires a non-empty id');
      return;
    }
    this.markFrame(connectionId);
    if (!this.dispatcher.isBusinessEvent(event)) {
      this.sendAckError(socket, id, 'UNKNOWN_EVENT', '未知事件');
      return;
    }
    const payload = 'payload' in frame ? frame.payload : undefined;
    this.dispatcher.handleCommand(
      {
        connectionId,
        sendAck: (result) => {
          if (result.ok) {
            this.sendRaw(socket, { v: PROTOCOL_VERSION, id, ok: true, data: result.data === undefined ? null : result.data });
          } else {
            this.sendRaw(socket, { v: PROTOCOL_VERSION, id, ok: false, error: result.error });
          }
        },
        close: () => {
          try {
            socket.close(1008, 'rate limited');
          } catch {
            // Socket already gone.
          }
        },
      },
      event,
      payload,
    );
  }

  private onClose(connectionId: string): void {
    this.idle.delete(connectionId);
    this.registry.unregister(connectionId);
    this.dispatcher.handleDisconnect(connectionId);
  }

  private markFrame(connectionId: string): void {
    const tracker = this.idle.get(connectionId);
    if (tracker) tracker.lastFrameAt = Date.now();
  }

  private sweep(): void {
    const now = Date.now();
    for (const tracker of this.idle.values()) {
      if (now - tracker.lastFrameAt > this.idleTimeoutMs) {
        try {
          tracker.socket.close(1000, 'idle timeout');
        } catch {
          // Socket already gone.
        }
      }
    }
  }

  private protocolViolation(socket: WebSocket, reason: string): void {
    this.logger.warn({ event: 'ws_protocol_violation', reason });
    try {
      socket.close(1002, reason);
    } catch {
      // Socket already gone.
    }
  }

  private sendAckError(socket: WebSocket, id: string | null, code: string, message: string): void {
    const frame: Record<string, unknown> = { v: PROTOCOL_VERSION, ok: false, error: { code, message } };
    if (id !== null) frame.id = id;
    this.sendRaw(socket, frame);
  }

  private sendRaw(socket: WebSocket, frame: object): void {
    if (socket.readyState !== socket.OPEN) return;
    try {
      socket.send(JSON.stringify(frame));
    } catch (error) {
      this.logger.warn({ event: 'ws_send_failed', message: (error as Error).message });
    }
  }
}

function idOf(frame: Envelope): string | null {
  return typeof frame.id === 'string' && frame.id.length > 0 ? frame.id : null;
}
